locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Track       = "enterprise-ecs"
    ManagedBy   = "terraform"
    Repository  = var.repository
    CostCenter  = "platform-engineering"
    Owner       = "platform-team"
  }

  # Cost mode (default): no NAT gateway, so tasks run in public subnets with a
  # public IP and the security group still limits ingress to the ALB only.
  # Production mode: tasks run in private subnets and reach ECR/Secrets via NAT.
  task_subnet_ids  = var.enable_nat_gateway ? module.vpc.private_subnet_ids : module.vpc.public_subnet_ids
  task_public_ip   = !var.enable_nat_gateway
  api_image        = "${module.ecr.api_repository_url}:${var.image_tag}"
  web_image        = "${module.ecr.web_repository_url}:${var.image_tag}"
  cluster_name     = var.enable_services ? module.ecs[0].cluster_name : "${local.name_prefix}-cluster"
  api_service_name = var.enable_services ? module.ecs[0].api_service_name : "${local.name_prefix}-api"
}
