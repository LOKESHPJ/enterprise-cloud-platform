# Runbook

## One-time bootstrap

Run once per AWS account, in CloudShell or any admin shell:

```bash
REPO=LOKESHPJ/enterprise-cloud-platform bash scripts/bootstrap.sh
```

Creates the OIDC provider, the two deploy roles, the S3 state bucket with versioning
and encryption, and the DynamoDB lock table. Creates **no access keys**.

Then set repository variables (the script prints the exact values):

| Variable | Value |
|---|---|
| `TF_STATE_BUCKET` | `cloudforge-tfstate-<account-id>` |
| `AWS_SERVERLESS_ROLE_ARN` | `arn:aws:iam::<account>:role/cloudforge-gha-serverless` |
| `AWS_TERRAFORM_ROLE_ARN` | `arn:aws:iam::<account>:role/cloudforge-gha-terraform` |

Workflows fall back to these same values if the variables are absent, so the first run
works before you configure anything. Set them explicitly for clarity.

Optional but recommended: protect the `production-enterprise` environment. Open Settings,
then Environments, and add yourself as a required reviewer. That turns the enterprise apply
into a two-person decision even if someone types the confirmation phrase.

## Deploy the free track

Automatic on push to `main`. To run it by hand, open Actions, pick **Deploy serverless (free
tier)** and press Run.

Verify:

```bash
curl -s "$(terraform -chdir=infrastructure/serverless output -raw health_url)"
curl -s "$(terraform -chdir=infrastructure/serverless output -raw site_url)" -o /dev/null -w '%{http_code}\n'
```

## Deploy the enterprise stack

1. Open Actions, run **Deploy enterprise stack** with `confirm=DEPLOY-BILLABLE` and
   `enable_services=false`. That creates the VPC, ALB, RDS, ECR, secret and alarms.
2. Run **Build and push images**. Wait until both images are in ECR.
3. Run **Deploy enterprise stack** again with `enable_services=true`. The `verify` job polls
   `http://<alb>/api/health` until it returns 200.

The environment `production-enterprise` is attached to the apply job; if you configured
required reviewers, the job pauses there.

## Roll back a bad deployment

**Serverless (live track):** the pipeline does it for you. If any smoke test fails
after the alias moves, the `Roll back alias after failed verification` step points the
`live` alias back at the previous version. To do it by hand:

```bash
FUNCTION=cloudforge-dev-api
VERSIONS=$(aws lambda list-versions-by-function --function-name "$FUNCTION" \
  --query 'Versions[].Version' --output text | tr '\t' '\n' | sort -n)
CURRENT=$(aws lambda get-alias --function-name "$FUNCTION" --name live --query FunctionVersion --output text)
PREVIOUS=$(echo "$VERSIONS" | awk -v c="$CURRENT" '$1 < c' | tail -1)
aws lambda update-alias --function-name "$FUNCTION" --name live --function-version "$PREVIOUS"
```

No rebuild, no Terraform, seconds to complete.

**ECS (enterprise):** the circuit breaker already did it if health checks failed. If it
did not, redeploy the previous image tag:

```
Run Deploy enterprise stack again with enable_services=true and image_tag=sha-<previous commit>
```

Terraform registers a new task definition revision; the service shifts traffic only to
healthy targets. To roll back by hand:

```bash
aws ecs update-service --cluster cloudforge-dev-cluster --service cloudforge-dev-api \
  --task-definition cloudforge-dev-api:<previous-revision> --force-new-deployment
```

**Frontend:** the S3 objects rely on cache control rather than bucket versioning, so rolling
the frontend back means rebuilding the previous commit. `git revert` followed by a push is the
intended path.

## Investigate an incident

| Question | Command |
|---|---|
| Is the API healthy? | `curl -s https://<host>/api/health \| jq` |
| Are targets passing? | `aws elbv2 describe-target-health --target-group-arn <arn>` |
| Which alarms are firing? | `aws cloudwatch describe-alarms --state-value ALARM` |
| Recent API logs (enterprise) | `aws logs tail /ecs/cloudforge-dev/api --since 30m --follow` |
| Recent Lambda logs | `aws logs tail /aws/lambda/cloudforge-dev-api --since 30m --follow` |
| API access logs | `aws logs tail /aws/apigateway/cloudforge-dev-http-api --since 30m` |
| Why did a task stop? | `aws ecs describe-tasks --cluster cloudforge-dev-cluster --tasks <arn>` |
| Is the database reachable? | check the `db_cpu` / `db_storage` alarms; the DB is not internet-facing |

Common causes:

- **503 from `/api/health`:** the storage backend is unreachable. On the enterprise track,
  check the RDS security group or exhausted connections. On the live track, check the DynamoDB
  table name and the function's IAM policy.
- **502 from the ALB:** no healthy targets. Look at the task stop reason and the API log group.
- **Blank page from CloudFront:** the SPA was built without `VITE_API_BASE_URL`. Check the
  `ship` job log and rebuild.
- **CORS error in the browser:** `allowed_origins` does not include the site origin.

## Scaling

API autoscaling tracks CPU at 60 percent and moves between 2 and 6 tasks. To raise the ceiling,
change `max_capacity` in `modules/ecs` and apply. The web service has no autoscaling by
default, so raise `web_desired_count` instead.

## Rotate the database password

The password lives in Secrets Manager and is generated by Terraform, so rotation means
replacing the secret and rolling the service:

```bash
aws secretsmanager put-secret-value --secret-id cloudforge-dev/rds/credentials \
  --secret-string '{"username":"platform","password":"<new>","dbname":"platform","engine":"postgres","port":5432}'
aws rds modify-db-instance --db-instance-identifier cloudforge-dev-postgres \
  --master-user-password '<new>' --apply-immediately
aws ecs update-service --cluster cloudforge-dev-cluster --service cloudforge-dev-api --force-new-deployment
```

Terraform will detect the drift on the next plan; either import the state back or
`terraform apply -refresh-only` and accept the new value.

## Teardown

| Track | Action |
|---|---|
| Serverless | Run **Destroy serverless**, then type `destroy` |
| Enterprise | Run **Destroy enterprise stack**, then type `DESTROY-BILLABLE` |

Verify nothing billable remains:

```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier'
aws ecs list-clusters
aws ec2 describe-nat-gateways --filter Name=state,Values=available
```

The state bucket and lock table are intentionally left behind (a few cents per month at
most) so the stack can be recreated with history intact. Delete them manually if you want
a completely clean account.

## Rotate the GitHub credential used by this repository

If a personal access token was used to bootstrap the repository, revoke it under Settings,
then Developer settings, then Tokens (classic), and rely on the OIDC roles afterwards. The
workflows never need a stored GitHub token.
