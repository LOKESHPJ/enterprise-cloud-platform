output "secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  value = aws_secretsmanager_secret.db.name
}

output "password" {
  description = "Generated database password, consumed by the RDS module."
  value       = random_password.db.result
  sensitive   = true
}
