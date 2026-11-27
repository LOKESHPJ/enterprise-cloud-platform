# Release safety: CodeDeploy canary for the Lambda alias, plus a spend guardrail.
#
# The alias (see lambda.tf) is the unit CodeDeploy shifts traffic between:
#   10% of traffic to the new version for 5 minutes, then 100%.
# If either alarm fires during that window, CodeDeploy stops and rolls the alias
# back to the previous version automatically. No human in the loop.

resource "aws_codedeploy_app" "api" {
  name             = "${local.name_prefix}-api"
  compute_platform = "Lambda"

  tags = {
    Name = "${local.name_prefix}-api"
  }
}

data "aws_iam_policy_document" "codedeploy_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codedeploy" {
  name               = "${local.name_prefix}-codedeploy"
  description        = "Allows CodeDeploy to shift traffic between Lambda versions"
  assume_role_policy = data.aws_iam_policy_document.codedeploy_assume.json

  tags = {
    Name = "${local.name_prefix}-codedeploy"
  }
}

resource "aws_iam_role_policy_attachment" "codedeploy_lambda" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForLambda"
}

resource "aws_codedeploy_deployment_group" "api" {
  app_name               = aws_codedeploy_app.api.name
  deployment_group_name  = "${local.name_prefix}-api-live"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = "CodeDeployDefault.LambdaCanary10Percent5Minutes"

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  # Roll back on a failed deployment or when an alarm trips mid-shift.
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  alarm_configuration {
    enabled                   = true
    alarms                    = [aws_cloudwatch_metric_alarm.lambda_errors.alarm_name, aws_cloudwatch_metric_alarm.api_5xx.alarm_name]
    ignore_poll_alarm_failure = false
  }

  tags = {
    Name = "${local.name_prefix}-api-live"
  }
}

# ---------------------------------------------------------------------------
# Cost governance
#
# An account-level monthly budget with email thresholds. Deliberately no cost
# filter: a single-purpose account is easier to reason about as one number, and
# tag-based budgets silently read zero when cost allocation tags are inactive.
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "${local.name_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = var.alert_email == "" ? [] : [50, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
    }
  }
}
