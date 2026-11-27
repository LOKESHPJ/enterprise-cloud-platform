terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Track       = "serverless-free-tier"
    ManagedBy   = "terraform"
    Repository  = var.repository
    CostCenter  = "platform-engineering"
    Owner       = "platform-team"
  }

  name_prefix = "${var.project}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
}
