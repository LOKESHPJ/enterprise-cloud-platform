variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets for the Fargate tasks. Public subnets with public IPs when no NAT gateway exists."
  type        = list(string)
}

variable "assign_public_ip" {
  description = "True in cost mode (no NAT gateway), false in production mode (private subnets + NAT)."
  type        = bool
  default     = true
}

variable "security_group_id" {
  type = string
}

variable "api_image" {
  type = string
}

variable "web_image" {
  type = string
}

variable "image_tag" {
  type = string
}

variable "api_cpu" {
  description = "Fargate CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "api_memory" {
  type    = number
  default = 512
}

variable "web_cpu" {
  type    = number
  default = 256
}

variable "web_memory" {
  type    = number
  default = 512
}

variable "api_desired_count" {
  type    = number
  default = 2
}

variable "web_desired_count" {
  type    = number
  default = 1
}

variable "api_target_group_arn" {
  type = string
}

variable "web_target_group_arn" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "db_secret_arn" {
  type = string
}

variable "environment" {
  type = string
}

variable "cors_origins" {
  type    = string
  default = "*"
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled" # Container Insights is billed per metric; enable deliberately.
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-cluster" })
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.name_prefix}/api"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "${var.name_prefix}-api-logs" })
}

resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${var.name_prefix}/web"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "${var.name_prefix}-web-logs" })
}

# ------------------------------------------------------------------ API task
resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name_prefix}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.api_cpu
  memory                   = var.api_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = var.api_image
      essential = true

      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "STORAGE_BACKEND", value = "postgres" },
        { name = "ENVIRONMENT", value = var.environment },
        { name = "APP_VERSION", value = var.image_tag },
        { name = "CORS_ORIGINS", value = var.cors_origins },
        { name = "LOG_LEVEL", value = "INFO" },
        { name = "DB_HOST", value = var.db_host },
        { name = "DB_PORT", value = tostring(var.db_port) },
      ]

      secrets = [
        { name = "DB_USER", valueFrom = "${var.db_secret_arn}:username::" },
        { name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
        { name = "DB_NAME", valueFrom = "${var.db_secret_arn}:dbname::" },
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/health',timeout=3).status==200 else 1)\""]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "api"
        }
      }
    }
  ])

  tags = merge(var.tags, { Name = "${var.name_prefix}-api-task" })
}

# ------------------------------------------------------------------ WEB task
resource "aws_ecs_task_definition" "web" {
  family                   = "${var.name_prefix}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.web_cpu
  memory                   = var.web_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "web"
      image     = var.web_image
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "wget -q --spider http://127.0.0.1:8080/healthz || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.web.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "web"
        }
      }
    }
  ])

  tags = merge(var.tags, { Name = "${var.name_prefix}-web-task" })
}

# ----------------------------------------------------------------- services
resource "aws_ecs_service" "api" {
  name            = "${var.name_prefix}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_desired_count
  launch_type     = "FARGATE"

  platform_version = "LATEST"

  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = var.api_target_group_arn
    container_name   = "api"
    container_port   = 8000
  }

  # Failed deployments roll back to the previous task definition automatically.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  enable_execute_command = true

  lifecycle {
    ignore_changes = [desired_count] # autoscaling owns the count after the first apply
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-api-service" })
}

resource "aws_ecs_service" "web" {
  name            = "${var.name_prefix}-web"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = var.web_desired_count
  launch_type     = "FARGATE"

  platform_version = "LATEST"

  health_check_grace_period_seconds  = 30
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = var.web_target_group_arn
    container_name   = "web"
    container_port   = 8080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-web-service" })
}

# --------------------------------------------------------------- autoscaling
resource "aws_appautoscaling_target" "api" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 2
  max_capacity       = 6
}

resource "aws_appautoscaling_policy" "api_cpu" {
  name               = "${var.name_prefix}-api-cpu-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
