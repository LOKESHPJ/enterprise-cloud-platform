output "site_url" {
  description = "Public URL of the React frontend. HTTPS when CloudFront or the Lambda SPA is used."
  value = var.enable_cloudfront ? (
    "https://${aws_cloudfront_distribution.web[0].domain_name}"
    ) : (
    aws_apigatewayv2_api.api.api_endpoint
  )
}

output "frontend_hosting" {
  description = "cloudfront (private S3 + OAC) or lambda (SPA served by the API function over HTTPS)."
  value       = var.enable_cloudfront ? "cloudfront" : "lambda"
}

output "api_base_url" {
  description = "Base URL of the HTTP API. The frontend is built against this value."
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "health_url" {
  description = "Readiness endpoint used by CI to verify the deployment."
  value       = "${aws_apigatewayv2_api.api.api_endpoint}/api/health"
}

output "docs_url" {
  description = "OpenAPI documentation."
  value       = "${aws_apigatewayv2_api.api.api_endpoint}/api/docs"
}

output "frontend_bucket" {
  description = "S3 bucket that receives the built SPA bundle."
  value       = aws_s3_bucket.web.id
}

output "cloudfront_distribution_id" {
  description = "Distribution ID, used for cache invalidation after upload. Empty in S3 website mode."
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.web[0].id : ""
}

output "dynamodb_table" {
  description = "Single table data store."
  value       = aws_dynamodb_table.data.name
}

output "lambda_function_name" {
  description = "Application compute."
  value       = aws_lambda_function.api.function_name
}

output "lambda_alias" {
  description = "Alias that API Gateway invokes and the pipeline shifts on release."
  value       = aws_lambda_alias.live.name
}

output "budget_name" {
  description = "Account level monthly budget."
  value       = aws_budgets_budget.monthly.name
}

output "log_groups" {
  description = "CloudWatch log groups created and managed by Terraform."
  value = {
    lambda = aws_cloudwatch_log_group.lambda.name
    api    = aws_cloudwatch_log_group.api_access.name
  }
}
