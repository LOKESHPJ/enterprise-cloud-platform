variable "aws_region" {
  description = "Deployment region."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short project slug used in resource names."
  type        = string
  default     = "cloudforge"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging, prod."
  }
}

variable "repository" {
  description = "GitHub repository in owner/name form, recorded as a resource tag."
  type        = string
  default     = "LOKESHPJ/enterprise-cloud-platform"
}

variable "app_version" {
  description = "Version string reported by /api/health. CI passes the commit SHA."
  type        = string
  default     = "0.0.0-dev"
}

variable "lambda_zip_path" {
  description = "Path to the built Lambda deployment package (produced by CI)."
  type        = string
  default     = "../../dist/lambda.zip"
}

variable "lambda_memory_mb" {
  description = "Lambda memory. Free tier covers 400,000 GB-seconds per month."
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout. HTTP APIs cap integrations at 30 seconds."
  type        = number
  default     = 25
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for application and access logs."
  type        = number
  default     = 7
}

variable "allowed_origins" {
  description = "CORS origins for the API. Tighten to the CloudFront domain after the first apply."
  type        = list(string)
  default     = ["*"]
}

variable "monthly_budget_usd" {
  description = "Account level monthly budget threshold in USD. Alerts at 50/80/100 percent."
  type        = number
  default     = 1
}

variable "alert_email" {
  description = "Email address subscribed to budget alerts. Empty disables notifications."
  type        = string
  default     = ""
}
