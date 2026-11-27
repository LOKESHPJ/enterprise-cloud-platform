#!/usr/bin/env bash
# Bootstrap the one-time account prerequisites that Terraform cannot create for
# itself: the GitHub OIDC provider, the deployment roles, and the remote state
# backend (S3 + DynamoDB lock table).
#
# Run this in AWS CloudShell (or any shell with administrative credentials):
#   REPO=LOKESHPJ/enterprise-cloud-platform bash scripts/bootstrap.sh
#
# It is idempotent: re-running it converges instead of failing.

set -euo pipefail

REPO="${REPO:-LOKESHPJ/enterprise-cloud-platform}"
REGION="${REGION:-us-east-1}"
PROJECT="${PROJECT:-cloudforge}"

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="${PROJECT}-tfstate-${ACCOUNT}"
LOCK_TABLE="${PROJECT}-terraform-locks"
OIDC_HOST="token.actions.githubusercontent.com"
OIDC_ARN="arn:aws:iam::${ACCOUNT}:oidc-provider/${OIDC_HOST}"

# GitHub now issues immutable subject claims that embed numeric owner/repo IDs:
#   repo:OWNER@<owner-id>/REPO@<repo-id>:ref:refs/heads/main
# Both the classic and the immutable forms are allowed below so the role keeps
# working if the repository predates immutable subjects.
REPO_OWNER="${REPO%%/*}"
REPO_NAME="${REPO#*/}"

echo "==> Account ${ACCOUNT} / region ${REGION} / repo ${REPO}"

# ---------------------------------------------------------------- OIDC provider
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${OIDC_ARN}" >/dev/null 2>&1; then
  echo "==> OIDC provider already exists"
else
  echo "==> Creating OIDC provider for ${OIDC_HOST}"
  aws iam create-open-id-connect-provider \
    --url "https://${OIDC_HOST}" \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null
fi

# ------------------------------------------------------------- Terraform state
if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
  echo "==> State bucket exists: ${STATE_BUCKET}"
else
  echo "==> Creating state bucket ${STATE_BUCKET}"
  if [ "${REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${REGION}" >/dev/null
  else
    aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}" >/dev/null
  fi
fi

aws s3api put-bucket-versioning --bucket "${STATE_BUCKET}" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "${STATE_BUCKET}" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
aws s3api put-public-access-block --bucket "${STATE_BUCKET}" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-policy --bucket "${STATE_BUCKET}" --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Sid\": \"DenyInsecureTransport\",
    \"Effect\": \"Deny\",
    \"Principal\": \"*\",
    \"Action\": \"s3:*\",
    \"Resource\": [\"arn:aws:s3:::${STATE_BUCKET}\", \"arn:aws:s3:::${STATE_BUCKET}/*\"],
    \"Condition\": {\"Bool\": {\"aws:SecureTransport\": \"false\"}}
  }]
}"

if aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${REGION}" >/dev/null 2>&1; then
  echo "==> Lock table exists: ${LOCK_TABLE}"
else
  echo "==> Creating lock table ${LOCK_TABLE}"
  aws dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}" >/dev/null
fi

# ------------------------------------------------------------------ trust policy
TRUST_POLICY="$(mktemp)"
cat > "${TRUST_POLICY}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "${OIDC_ARN}" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_HOST}:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "${OIDC_HOST}:sub": [
            "repo:${REPO}:ref:refs/heads/main",
            "repo:${REPO}:environment:*",
            "repo:${REPO_OWNER}@*/${REPO_NAME}@*:ref:refs/heads/main",
            "repo:${REPO_OWNER}@*/${REPO_NAME}@*:environment:*"
          ]
        }
      }
    }
  ]
}
JSON

# ---------------------------------------------------------- serverless role
SERVERLESS_ROLE="${PROJECT}-gha-serverless"
if aws iam get-role --role-name "${SERVERLESS_ROLE}" >/dev/null 2>&1; then
  echo "==> Updating trust policy on ${SERVERLESS_ROLE}"
  aws iam update-assume-role-policy --role-name "${SERVERLESS_ROLE}" --policy-document "file://${TRUST_POLICY}"
else
  echo "==> Creating role ${SERVERLESS_ROLE}"
  aws iam create-role --role-name "${SERVERLESS_ROLE}" \
    --description "GitHub Actions: deploy the serverless (free tier) track" \
    --assume-role-policy-document "file://${TRUST_POLICY}" \
    --max-session-duration 3600 >/dev/null
fi

SERVERLESS_POLICY="$(mktemp)"
cat > "${SERVERLESS_POLICY}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformState",
      "Effect": "Allow",
      "Action": ["s3:Get*", "s3:Put*", "s3:List*", "s3:Delete*"],
      "Resource": "arn:aws:s3:::${PROJECT}-*"
    },
    {
      "Sid": "ObjectAccess",
      "Effect": "Allow",
      "Action": ["s3:Get*", "s3:Put*", "s3:Delete*"],
      "Resource": "arn:aws:s3:::${PROJECT}-*/*"
    },
    {
      "Sid": "BucketLifecycle",
      "Effect": "Allow",
      "Action": ["s3:CreateBucket", "s3:DeleteBucket", "s3:ListAllMyBuckets"],
      "Resource": "*"
    },
    {
      "Sid": "StateLock",
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"],
      "Resource": "arn:aws:dynamodb:${REGION}:${ACCOUNT}:table/${LOCK_TABLE}"
    },
    {
      "Sid": "ApplicationTable",
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable", "dynamodb:DeleteTable", "dynamodb:DescribeTable",
        "dynamodb:UpdateTable", "dynamodb:UpdateTimeToLive", "dynamodb:TagResource",
        "dynamodb:ListTagsOfResource", "dynamodb:DescribeContinuousBackups",
        "dynamodb:DescribeTimeToLive"
      ],
      "Resource": "arn:aws:dynamodb:${REGION}:${ACCOUNT}:table/${PROJECT}-*"
    },
    {
      "Sid": "Lambda",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:GetFunction",
        "lambda:GetFunctionConfiguration", "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration", "lambda:AddPermission",
        "lambda:RemovePermission", "lambda:GetPolicy",
        "lambda:ListVersionsByFunction", "lambda:PublishVersion",
        "lambda:TagResource", "lambda:UntagResource", "lambda:ListTags",
        "lambda:GetAccountSettings", "lambda:PutFunctionConcurrency",
        "lambda:GetFunctionCodeSigningConfig", "lambda:GetFunctionEventInvokeConfig",
        "lambda:GetFunctionUrlConfig", "lambda:ListTags"
      ],
      "Resource": "arn:aws:lambda:${REGION}:${ACCOUNT}:function:${PROJECT}-*"
    },
    {
      "Sid": "ApiGateway",
      "Effect": "Allow",
      "Action": "apigateway:*",
      "Resource": "arn:aws:apigateway:${REGION}::/*"
    },
    {
      "Sid": "CloudFront",
      "Effect": "Allow",
      "Action": "cloudfront:*",
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
        "logs:TagResource", "logs:UntagResource", "logs:ListTagsForResource",
        "logs:PutResourcePolicy", "logs:DeleteResourcePolicy",
        "logs:DescribeResourcePolicies"
      ],
      "Resource": "arn:aws:logs:${REGION}:${ACCOUNT}:log-group:*"
    },
    {
      "Sid": "ApiGatewayAccessLogging",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogDelivery", "logs:DeleteLogDelivery", "logs:GetLogDelivery",
        "logs:UpdateLogDelivery", "logs:ListLogDeliveries"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LambdaVersionsAndAliases",
      "Effect": "Allow",
      "Action": [
        "lambda:PublishVersion", "lambda:CreateAlias", "lambda:DeleteAlias",
        "lambda:GetAlias", "lambda:UpdateAlias", "lambda:ListAliases",
        "lambda:ListVersionsByFunction"
      ],
      "Resource": "arn:aws:lambda:${REGION}:${ACCOUNT}:function:${PROJECT}-*"
    },
    {
      "Sid": "CodeDeployCanary",
      "Effect": "Allow",
      "Action": "codedeploy:*",
      "Resource": "*"
    },
    {
      "Sid": "BudgetGuardrail",
      "Effect": "Allow",
      "Action": ["budgets:ModifyBudget", "budgets:ViewBudget", "budgets:TagResource",
                 "budgets:UntagResource", "budgets:ListTagsForResource"],
      "Resource": "arn:aws:budgets::${ACCOUNT}:budget/*"
    },
    {
      "Sid": "CloudwatchAlarms",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms", "cloudwatch:PutDashboard",
        "cloudwatch:DeleteDashboards", "cloudwatch:GetDashboard",
        "cloudwatch:ListTagsForResource", "cloudwatch:TagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LambdaExecutionRole",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:PassRole",
        "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies", "iam:ListRolePolicies",
        "iam:ListInstanceProfilesForRole",
        "iam:TagRole", "iam:UntagRole", "iam:UpdateAssumeRolePolicy"
      ],
      "Resource": "arn:aws:iam::${ACCOUNT}:role/${PROJECT}-*"
    }
  ]
}
JSON

aws iam put-role-policy --role-name "${SERVERLESS_ROLE}" \
  --policy-name "serverless-deploy" --policy-document "file://${SERVERLESS_POLICY}"

# ---------------------------------------------------------- enterprise role
TERRAFORM_ROLE="${PROJECT}-gha-terraform"
if aws iam get-role --role-name "${TERRAFORM_ROLE}" >/dev/null 2>&1; then
  echo "==> Updating trust policy on ${TERRAFORM_ROLE}"
  aws iam update-assume-role-policy --role-name "${TERRAFORM_ROLE}" --policy-document "file://${TRUST_POLICY}"
else
  echo "==> Creating role ${TERRAFORM_ROLE}"
  aws iam create-role --role-name "${TERRAFORM_ROLE}" \
    --description "GitHub Actions: provision the billable enterprise track (gated by environment approval)" \
    --assume-role-policy-document "file://${TRUST_POLICY}" \
    --max-session-duration 3600 >/dev/null
fi

aws iam detach-role-policy --role-name "${TERRAFORM_ROLE}" \
  --policy-arn "arn:aws:iam::aws:policy/PowerUserAccess" 2>/dev/null || true
aws iam detach-role-policy --role-name "${TERRAFORM_ROLE}" \
  --policy-arn "arn:aws:iam::aws:policy/IAMFullAccess" 2>/dev/null || true

# Scoped platform policy.
#
# Deliberately NOT PowerUserAccess: this role can only touch the service
# families the platform provisions, only IAM roles and policies under the
# ${PROJECT}- prefix, and only the state bucket and lock table. It cannot read
# arbitrary S3 data, cannot touch IAM users or keys (also denied explicitly
# below), and cannot reach Organizations or the Account API.
echo "==> Applying scoped platform policy to ${TERRAFORM_ROLE}"
TERRAFORM_POLICY="$(mktemp)"
cat > "${TERRAFORM_POLICY}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Discover",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*", "ecs:Describe*", "ecs:List*", "ecr:Describe*",
        "ecr:List*", "rds:Describe*", "elasticloadbalancing:Describe*",
        "cloudwatch:Describe*", "cloudwatch:List*", "logs:Describe*",
        "application-autoscaling:Describe*", "autoscaling:Describe*",
        "kms:DescribeKey", "kms:ListAliases", "kms:ListResourceTags",
        "sts:GetCallerIdentity", "tag:GetResources"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Networking",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
        "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute",
        "ec2:DeleteRoute", "ec2:ReplaceRoute", "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable", "ec2:ReplaceRouteTableAssociation",
        "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
        "ec2:AllocateAddress", "ec2:ReleaseAddress",
        "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
        "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
        "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Containers",
      "Effect": "Allow",
      "Action": [
        "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:ListTagsForResource",
        "ecr:TagResource", "ecr:PutLifecyclePolicy", "ecr:GetLifecyclePolicy",
        "ecr:DeleteLifecyclePolicy", "ecr:PutImageScanningConfiguration",
        "ecr:SetRepositoryPolicy", "ecr:DeleteRepositoryPolicy",
        "ecs:CreateCluster", "ecs:DeleteCluster", "ecs:UpdateCluster",
        "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition",
        "ecs:TagResource", "ecs:UntagResource",
        "ecs:CreateService", "ecs:UpdateService", "ecs:DeleteService"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LoadBalancing",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:SetSecurityGroups", "elasticloadbalancing:SetSubnets",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:ModifyTargetGroupAttributes",
        "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule",
        "elasticloadbalancing:ModifyRule",
        "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Database",
      "Effect": "Allow",
      "Action": [
        "rds:CreateDBInstance", "rds:DeleteDBInstance", "rds:ModifyDBInstance",
        "rds:CreateDBSubnetGroup", "rds:DeleteDBSubnetGroup",
        "rds:ModifyDBSubnetGroup", "rds:CreateDBParameterGroup",
        "rds:DeleteDBParameterGroup", "rds:ModifyDBParameterGroup",
        "rds:AddTagsToResource", "rds:RemoveTagsFromResource",
        "rds:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Secrets",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret",
        "secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecret",
        "secretsmanager:TagResource", "secretsmanager:UntagResource",
        "secretsmanager:GetResourcePolicy", "secretsmanager:PutResourcePolicy",
        "secretsmanager:DeleteResourcePolicy"
      ],
      "Resource": "arn:aws:secretsmanager:${REGION}:${ACCOUNT}:secret:${PROJECT}-*"
    },
    {
      "Sid": "Observability",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
        "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource",
        "logs:ListTagsForResource", "logs:DescribeLogGroups",
        "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms", "cloudwatch:PutDashboard",
        "cloudwatch:DeleteDashboards", "cloudwatch:GetDashboard",
        "cloudwatch:TagResource", "cloudwatch:UntagResource",
        "cloudwatch:ListTagsForResource",
        "application-autoscaling:RegisterScalableTarget",
        "application-autoscaling:DeregisterScalableTarget",
        "application-autoscaling:PutScalingPolicy",
        "application-autoscaling:DeleteScalingPolicy",
        "application-autoscaling:TagResource", "application-autoscaling:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ProjectRolesOnly",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:PassRole",
        "iam:TagRole", "iam:UntagRole", "iam:PutRolePolicy",
        "iam:DeleteRolePolicy", "iam:GetRolePolicy",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy",
        "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
        "iam:UpdateAssumeRolePolicy", "iam:ListInstanceProfilesForRole"
      ],
      "Resource": "arn:aws:iam::${ACCOUNT}:role/${PROJECT}-*"
    },
    {
      "Sid": "TerraformState",
      "Effect": "Allow",
      "Action": ["s3:Get*", "s3:Put*", "s3:List*", "s3:Delete*"],
      "Resource": "arn:aws:s3:::${PROJECT}-tfstate-${ACCOUNT}"
    },
    {
      "Sid": "TerraformStateObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::${PROJECT}-tfstate-${ACCOUNT}/*"
    },
    {
      "Sid": "StateLock",
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"],
      "Resource": "arn:aws:dynamodb:${REGION}:${ACCOUNT}:table/${LOCK_TABLE}"
    }
  ]
}
JSON

aws iam put-role-policy --role-name "${TERRAFORM_ROLE}" \
  --policy-name "platform-scoped-deploy" --policy-document "file://${TERRAFORM_POLICY}"

echo "==> Denying the enterprise role permission to touch IAM users or access keys"
DENY_POLICY="$(mktemp)"
cat > "${DENY_POLICY}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "NoIdentityEscalation",
      "Effect": "Deny",
      "Action": [
        "iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile",
        "iam:UpdateLoginProfile", "iam:AttachUserPolicy", "iam:PutUserPolicy",
        "iam:CreateVirtualMFADevice", "iam:DeactivateMFADevice",
        "organizations:*", "account:*"
      ],
      "Resource": "*"
    }
  ]
}
JSON
aws iam put-role-policy --role-name "${TERRAFORM_ROLE}" \
  --policy-name "no-identity-escalation" --policy-document "file://${DENY_POLICY}"

# -------------------------------------------------------------------- summary
cat <<EOF

================================================================
Bootstrap complete.

Set these GitHub repository variables (Settings > Secrets and variables > Actions > Variables):

  TF_STATE_BUCKET        = ${STATE_BUCKET}
  AWS_SERVERLESS_ROLE_ARN = arn:aws:iam::${ACCOUNT}:role/${SERVERLESS_ROLE}
  AWS_TERRAFORM_ROLE_ARN  = arn:aws:iam::${ACCOUNT}:role/${TERRAFORM_ROLE}

Or with the GitHub CLI:

  gh variable set TF_STATE_BUCKET --body "${STATE_BUCKET}" --repo ${REPO}
  gh variable set AWS_SERVERLESS_ROLE_ARN --body "arn:aws:iam::${ACCOUNT}:role/${SERVERLESS_ROLE}" --repo ${REPO}
  gh variable set AWS_TERRAFORM_ROLE_ARN --body "arn:aws:iam::${ACCOUNT}:role/${TERRAFORM_ROLE}" --repo ${REPO}

No access keys were created. Workflows assume roles via OIDC only.
================================================================
EOF

rm -f "${TRUST_POLICY}" "${SERVERLESS_POLICY}" "${DENY_POLICY}"
