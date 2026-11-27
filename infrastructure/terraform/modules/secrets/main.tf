variable "name_prefix" {
  type = string
}

variable "db_username" {
  type    = string
  default = "platform"
}

variable "db_name" {
  type    = string
  default = "platform"
}

variable "recovery_window_days" {
  description = "0 deletes the secret immediately, which keeps teardown fast and free."
  type        = number
  default     = 0
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "random_password" "db" {
  length  = 32
  special = false # keeps the value safe inside a connection URI
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name_prefix}/rds/credentials"
  description             = "PostgreSQL credentials for the ${var.name_prefix} platform"
  recovery_window_in_days = var.recovery_window_days

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-credentials" })
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    dbname   = var.db_name
    engine   = "postgres"
    port     = 5432
  })
}
