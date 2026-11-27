variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "api_target_group_arn_suffix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "api_service_name" {
  type = string
}

variable "db_instance_identifier" {
  type = string
}

variable "alert_email" {
  description = "Optional address subscribed to the alert topic. Empty disables the subscription."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"

  tags = merge(var.tags, { Name = "${var.name_prefix}-alerts" })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# Edge failures: the ALB itself returning 5xx (no healthy targets, TLS problems).
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name_prefix}-alb-5xx"
  alarm_description   = "ALB is returning 5xx responses - traffic is not reaching healthy targets"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-5xx" })
}

# Application failures: responses from the API container itself.
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.name_prefix}-api-5xx"
  alarm_description   = "The API is returning 5xx responses"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.api_target_group_arn_suffix
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-api-5xx" })
}

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name          = "${var.name_prefix}-api-latency-p95"
  alarm_description   = "p95 response time above 2 seconds - check database latency and task CPU"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 2
  threshold           = 2
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.api_target_group_arn_suffix
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-api-latency-p95" })
}

resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${var.name_prefix}-rds-cpu"
  alarm_description   = "PostgreSQL CPU above 80% for 10 minutes"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-cpu" })
}

resource "aws_cloudwatch_metric_alarm" "db_storage" {
  alarm_name          = "${var.name_prefix}-rds-free-storage"
  alarm_description   = "PostgreSQL free storage below 2 GB"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2 * 1024 * 1024 * 1024
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-free-storage" })
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${var.name_prefix}-ecs-cpu-high"
  alarm_description   = "API service is running hot even after autoscaling headroom"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.api_service_name
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecs-cpu-high" })
}

resource "aws_cloudwatch_dashboard" "platform" {
  dashboard_name = "${var.name_prefix}-enterprise"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Requests, latency, errors"
          region = var.aws_region
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p95" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ECS service CPU and memory"
          region = var.aws_region
          period = 300
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.api_service_name],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.cluster_name, "ServiceName", var.api_service_name],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "PostgreSQL"
          region = var.aws_region
          period = 300
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_identifier],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_identifier],
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_instance_identifier],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Healthy and unhealthy targets"
          region = var.aws_region
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.api_target_group_arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.api_target_group_arn_suffix],
          ]
        }
      },
    ]
  })
}
