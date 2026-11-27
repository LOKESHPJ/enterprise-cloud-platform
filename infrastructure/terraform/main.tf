# ---------------------------------------------------------------------------
# Cost gate
#
# Everything below bills by the hour. This guard makes an accidental apply
# impossible: Terraform fails at plan time unless confirm_spend is explicitly
# set to true for the run.
# ---------------------------------------------------------------------------
resource "terraform_data" "spend_gate" {
  input = var.confirm_spend

  lifecycle {
    precondition {
      condition     = var.confirm_spend
      error_message = "Billable infrastructure is disabled. Review docs/COSTS.md, then run with -var=\"confirm_spend=true\" (the deploy-enterprise workflow also requires a manual environment approval)."
    }
  }
}

module "vpc" {
  source = "./modules/vpc"

  name_prefix             = local.name_prefix
  vpc_cidr                = var.vpc_cidr
  az_count                = var.az_count
  availability_zone_names = var.availability_zone_names
  enable_nat_gateway      = var.enable_nat_gateway
  tags                    = local.common_tags

  depends_on = [terraform_data.spend_gate]
}

module "ecr" {
  source = "./modules/ecr"

  name_prefix = local.name_prefix
  tags        = local.common_tags

  depends_on = [terraform_data.spend_gate]
}

module "secrets" {
  source = "./modules/secrets"

  name_prefix = local.name_prefix
  tags        = local.common_tags

  depends_on = [terraform_data.spend_gate]
}

module "iam" {
  source = "./modules/iam"

  name_prefix   = local.name_prefix
  db_secret_arn = module.secrets.secret_arn
  tags          = local.common_tags
}

module "rds" {
  source = "./modules/rds"

  name_prefix          = local.name_prefix
  private_subnet_ids   = module.vpc.private_subnet_ids
  security_group_id    = module.vpc.db_security_group_id
  instance_class       = var.db_instance_class
  allocated_storage_gb = var.db_allocated_storage_gb
  multi_az             = var.db_multi_az
  deletion_protection  = var.db_deletion_protection
  db_password          = module.secrets.password
  tags                 = local.common_tags
}

module "alb" {
  source = "./modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  security_group_id = module.vpc.alb_security_group_id
  certificate_arn   = var.certificate_arn
  tags              = local.common_tags
}

module "ecs" {
  source = "./modules/ecs"
  count  = var.enable_services ? 1 : 0

  name_prefix = local.name_prefix
  aws_region  = var.aws_region

  subnet_ids        = local.task_subnet_ids
  assign_public_ip  = local.task_public_ip
  security_group_id = module.vpc.app_security_group_id

  api_image = local.api_image
  web_image = local.web_image
  image_tag = var.image_tag

  api_cpu           = var.api_cpu
  api_memory        = var.api_memory
  api_desired_count = var.api_desired_count
  web_desired_count = var.web_desired_count

  api_target_group_arn = module.alb.api_target_group_arn
  web_target_group_arn = module.alb.web_target_group_arn

  execution_role_arn = module.iam.task_execution_role_arn
  task_role_arn      = module.iam.task_role_arn

  db_host            = module.rds.address
  db_port            = module.rds.port
  db_secret_arn      = module.secrets.secret_arn
  environment        = var.environment
  cors_origins       = var.cors_origins
  log_retention_days = var.log_retention_days

  tags = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix                 = local.name_prefix
  aws_region                  = var.aws_region
  alb_arn_suffix              = module.alb.arn_suffix
  api_target_group_arn_suffix = module.alb.api_target_group_arn_suffix
  cluster_name                = local.cluster_name
  api_service_name            = local.api_service_name
  db_instance_identifier      = module.rds.identifier
  alert_email                 = var.alert_email
  tags                        = local.common_tags
}
