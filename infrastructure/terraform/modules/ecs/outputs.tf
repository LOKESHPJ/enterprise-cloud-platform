output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "api_service_name" {
  value = aws_ecs_service.api.name
}

output "web_service_name" {
  value = aws_ecs_service.web.name
}

output "api_task_definition_arn" {
  value = aws_ecs_task_definition.api.arn
}

output "web_task_definition_arn" {
  value = aws_ecs_task_definition.web.arn
}

output "api_log_group" {
  value = aws_cloudwatch_log_group.api.name
}

output "web_log_group" {
  value = aws_cloudwatch_log_group.web.name
}
