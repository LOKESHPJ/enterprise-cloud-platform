variable "name_prefix" {
  type = string
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN the task execution role may read."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# NOTE ON BOOTSTRAP
# The GitHub Actions OIDC provider and the deploy roles are created by
# scripts/bootstrap.ps1 (or the documented CLI commands), not by Terraform.
# Terraform needs credentials to run, so it cannot create its own CI identity.

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.name_prefix}-task-execution"
  description        = "Pulls images from ECR and injects secrets into the task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = merge(var.tags, { Name = "${var.name_prefix}-task-execution" })
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_execution_extra" {
  statement {
    sid    = "ReadDatabaseSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [var.db_secret_arn]
  }

  statement {
    sid    = "DecryptSecret"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "task_execution_extra" {
  name   = "secret-and-kms-access"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_extra.json
}

# Application role: the container itself gets no AWS permissions beyond writing
# its own logs. Nothing in the app calls AWS APIs, so the policy is empty.
resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-task"
  description        = "Runtime identity for the application container (least privilege)"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = merge(var.tags, { Name = "${var.name_prefix}-task" })
}

data "aws_region" "current" {}
