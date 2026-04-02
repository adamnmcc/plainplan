output "api_invoke_url" {
  description = "Default API Gateway invoke URL"
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.api.function_name
}

output "custom_domain_target" {
  description = "DNS target to use for CNAME when custom domain is enabled"
  value = local.custom_domain_enabled ? {
    target_domain_name = aws_apigatewayv2_domain_name.custom[0].domain_name_configuration[0].target_domain_name
    hosted_zone_id     = aws_apigatewayv2_domain_name.custom[0].domain_name_configuration[0].hosted_zone_id
  } : null
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
