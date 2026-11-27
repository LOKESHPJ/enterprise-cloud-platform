variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "ecp"
}

variable "environment" {
  type    = string
  default = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging, prod."
  }
}

variable "repository" {
  description = "GitHub repository in owner/name form, used for tagging."
  type        = string
  default     = "LOKESHPJ/enterprise-cloud-platform"
}

# ---------------------------------------------------------------- cost controls
variable "confirm_spend" {
  description = <<-EOT
    Hard gate. The enterprise stack bills hourly (ALB, Fargate, RDS). Terraform
    refuses to plan or apply until this is explicitly true. See docs/COSTS.md.
  EOT
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Production networking: private subnets with NAT. Adds ~$32/month per AZ."
  type        = bool
  default     = false
}

variable "enable_services" {
  description = <<-EOT
    Two-phase deploy. Leave false on the first apply so ECR exists, push the
    images, then set true to create the ECS services.
  EOT
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- networking
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

# ---------------------------------------------------------------- application
variable "image_tag" {
  description = "Image tag deployed to ECS. CI uses sha-<commit>."
  type        = string
  default     = "sha-bootstrap"
}

variable "api_desired_count" {
  type    = number
  default = 2
}

variable "web_desired_count" {
  type    = number
  default = 1
}

variable "api_cpu" {
  type    = number
  default = 256
}

variable "api_memory" {
  type    = number
  default = 512
}

variable "cors_origins" {
  description = "Comma separated origins allowed to call the API. Defaults to the ALB origin (same-origin SPA)."
  type        = string
  default     = "*"
}

# --------------------------------------------------------------------- database
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_allocated_storage_gb" {
  type    = number
  default = 20
}

variable "db_deletion_protection" {
  type    = bool
  default = false
}

# ------------------------------------------------------------------ operations
variable "log_retention_days" {
  type    = number
  default = 7
}

variable "alert_email" {
  description = "Optional email for CloudWatch alarm notifications."
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "Optional ACM certificate ARN to enable HTTPS on the ALB."
  type        = string
  default     = ""
}
