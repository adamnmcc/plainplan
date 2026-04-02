# -------------------------------------------------------------------
# AWS Secrets Manager + SSM Parameter Store entries for deploy config.
#
# Terraform creates the secret shells. Populate real values via CLI:
#
#   aws secretsmanager put-secret-value \
#     --secret-id plainplan/dev/OPENROUTER_API_KEY \
#     --secret-string 'sk-or-v1-...' --region eu-west-1
#
# Terraform reads the values directly via data sources — no secrets
# flow through CI. Lambda gets them as env vars from Terraform.
# -------------------------------------------------------------------

variable "config_prefix" {
  description = "Prefix for deploy config in Secrets Manager / SSM (e.g. plainplan/dev)"
  type        = string
  default     = "plainplan/dev"
}

# ---- Secrets Manager (sensitive values) ----

resource "aws_secretsmanager_secret" "openrouter_api_key" {
  name        = "${var.config_prefix}/OPENROUTER_API_KEY"
  description = "OpenRouter API key for PlanPlain AI analysis"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret" "openrouter_base_url" {
  name        = "${var.config_prefix}/OPENROUTER_BASE_URL"
  description = "OpenRouter API base URL"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret" "stats_secret" {
  name        = "${var.config_prefix}/STATS_SECRET"
  description = "Bearer token for /api/stats endpoint"
  tags        = local.common_tags
}

# ---- Read secret values (empty string on first deploy before population) ----

data "aws_secretsmanager_secret_version" "openrouter_api_key" {
  secret_id  = aws_secretsmanager_secret.openrouter_api_key.id
  depends_on = [aws_secretsmanager_secret.openrouter_api_key]
}

data "aws_secretsmanager_secret_version" "openrouter_base_url" {
  secret_id  = aws_secretsmanager_secret.openrouter_base_url.id
  depends_on = [aws_secretsmanager_secret.openrouter_base_url]
}

data "aws_secretsmanager_secret_version" "stats_secret" {
  secret_id  = aws_secretsmanager_secret.stats_secret.id
  depends_on = [aws_secretsmanager_secret.stats_secret]
}

locals {
  # Read from data source; fall back to empty on first deploy.
  secret_openrouter_api_key  = try(data.aws_secretsmanager_secret_version.openrouter_api_key.secret_string, "")
  secret_openrouter_base_url = try(data.aws_secretsmanager_secret_version.openrouter_base_url.secret_string, "https://openrouter.ai/api/v1")
  secret_stats_secret        = try(data.aws_secretsmanager_secret_version.stats_secret.secret_string, "")
}

# ---- SSM Parameters (non-sensitive config) ----

resource "aws_ssm_parameter" "aws_region" {
  name  = "/${var.config_prefix}/AWS_REGION"
  type  = "String"
  value = var.aws_region
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "environment" {
  name  = "/${var.config_prefix}/ENVIRONMENT"
  type  = "String"
  value = var.environment
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "project_name" {
  name  = "/${var.config_prefix}/PROJECT_NAME"
  type  = "String"
  value = var.project_name
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "enable_aurora_serverless" {
  name  = "/${var.config_prefix}/ENABLE_AURORA_SERVERLESS"
  type  = "String"
  value = tostring(var.enable_aurora_serverless)
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "aurora_database_name" {
  name  = "/${var.config_prefix}/AURORA_DATABASE_NAME"
  type  = "String"
  value = var.aurora_database_name
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "aurora_min_capacity" {
  name  = "/${var.config_prefix}/AURORA_MIN_CAPACITY"
  type  = "String"
  value = tostring(var.aurora_min_capacity)
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "aurora_max_capacity" {
  name  = "/${var.config_prefix}/AURORA_MAX_CAPACITY"
  type  = "String"
  value = tostring(var.aurora_max_capacity)
  tags  = local.common_tags
}
