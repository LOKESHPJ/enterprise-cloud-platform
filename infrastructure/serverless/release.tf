# Release safety and cost guardrail.
#
# The Lambda alias (lambda.tf) is the unit of release: API Gateway invokes
# "live", and a release means moving that alias to a new immutable version.
# The pipeline verifies after the switch and moves the alias back to the
# previous version if verification fails - see .github/workflows/deploy-serverless.yml.
#
# AWS CodeDeploy would give a true canary with alarm-driven rollback, but it is
# unavailable on this account until AWS finishes verification
# (SubscriptionRequiredException), so the pipeline owns the shift and rollback.

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
