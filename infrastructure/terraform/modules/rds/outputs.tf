output "address" {
  value = aws_db_instance.this.address
}

output "endpoint" {
  value = aws_db_instance.this.endpoint
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "identifier" {
  value = aws_db_instance.this.identifier
}

output "database_url" {
  description = "SQLAlchemy connection URI used by the API task."
  value       = "postgresql+psycopg2://${var.db_username}:${var.db_password}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.db_name}"
  sensitive   = true
}
