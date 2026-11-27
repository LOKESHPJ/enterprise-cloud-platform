output "application_url" {
  description = "Public URL of the platform (ALB DNS name)."
  value       = "http://${module.alb.dns_name}"
}

output "alb_dns_name" {
  value = module.alb.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID, needed when pointing Route 53 at the ALB."
  value       = module.alb.zone_id
}

output "api_health_url" {
  value = "http://${module.alb.dns_name}/api/health"
}

output "api_docs_url" {
  value = "http://${module.alb.dns_name}/api/docs"
}

output "ecr_api_repository" {
  value = module.ecr.api_repository_url
}

output "ecr_web_repository" {
  value = module.ecr.web_repository_url
}

output "ecs_cluster_name" {
  value = local.cluster_name
}

output "api_service_name" {
  value = local.api_service_name
}

output "database_endpoint" {
  description = "RDS endpoint. Not reachable from the internet by design."
  value       = module.rds.endpoint
  sensitive   = true
}

output "db_secret_name" {
  value = module.secrets.secret_name
}

output "cloudwatch_dashboard" {
  value = module.monitoring.dashboard_name
}

output "alert_topic_arn" {
  value = module.monitoring.alert_topic_arn
}
