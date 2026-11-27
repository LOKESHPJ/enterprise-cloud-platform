# Lambda function running the same FastAPI app as the ECS track, adapted by Mangum.

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name_prefix}-api-lambda"
  description        = "Execution role for the ${local.name_prefix} HTTP API"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = {
    Name = "${local.name_prefix}-api-lambda"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_data" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:DescribeTable",
    ]
    resources = [
      aws_dynamodb_table.data.arn,
      "${aws_dynamodb_table.data.arn}/index/gsi1",
    ]
  }
}

resource "aws_iam_role_policy" "lambda_data" {
  name   = "data-access"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_data.json
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-api"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "api" {
  function_name    = "${local.name_prefix}-api"
  description      = "FastAPI catalogue and order service"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "lambda_handler.handler"
  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  memory_size      = var.lambda_memory_mb
  timeout          = var.lambda_timeout_seconds
  architectures    = ["x86_64"]

  # Immutable versions are what CodeDeploy shifts traffic between.
  publish = true

  environment {
    variables = {
      STORAGE_BACKEND = "dynamodb"
      TABLE_NAME      = aws_dynamodb_table.data.name
      ENVIRONMENT     = var.environment
      APP_VERSION     = var.app_version
      CORS_ORIGINS    = join(",", var.allowed_origins)
      LOG_LEVEL       = "INFO"
    }
  }

  tracing_config {
    mode = "PassThrough"
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda_data,
  ]

  tags = {
    Name = "${local.name_prefix}-api"
  }
}

# API Gateway invokes the alias, never $LATEST. CodeDeploy owns the alias's
# function_version, so Terraform must not fight it for control.
resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Serving alias for ${local.name_prefix}; shifted by CodeDeploy canary"
  function_name    = aws_lambda_function.api.function_name
  function_version = aws_lambda_function.api.version

  lifecycle {
    ignore_changes = [function_version]
  }
}
