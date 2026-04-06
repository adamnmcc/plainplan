output "api_invoke_url" {
  description = "Default API Gateway invoke URL"
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.api.function_name
}

output "custom_domain_target" {
  description = "API custom domain URL when enabled"
  value       = local.api_domain_enabled ? local.api_origin : null
}

output "api_custom_domain_url" {
  description = "API custom domain URL when enabled"
  value       = local.api_domain_enabled ? local.api_origin : null
}

output "website_url" {
  description = "Website URL when enabled"
  value       = local.website_domain_enabled ? local.website_origin : null
}

output "aurora_cluster_arn" {
  description = "Aurora cluster ARN when enable_aurora_serverless is true"
  value       = local.aurora_enabled ? aws_rds_cluster.aurora[0].arn : ""
}

output "aurora_secret_arn" {
  description = "Secrets Manager ARN for Aurora master credentials"
  value       = local.aurora_enabled ? aws_secretsmanager_secret.aurora_master[0].arn : ""
}

output "aurora_database_name" {
  description = "Aurora database name"
  value       = local.aurora_enabled ? var.aurora_database_name : ""
}

output "aurora_endpoint" {
  description = "Aurora writer endpoint"
  value       = local.aurora_enabled ? aws_rds_cluster.aurora[0].endpoint : ""
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port)"
  value       = local.rds_enabled ? aws_db_instance.postgres[0].endpoint : ""
}

output "rds_database_name" {
  description = "RDS database name"
  value       = local.rds_enabled ? var.rds_database_name : ""
}

output "rds_database_url" {
  description = "Full DATABASE_URL for direct psycopg connections"
  value       = local.rds_database_url
  sensitive   = true
}
