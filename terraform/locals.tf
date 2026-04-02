# Keep app settings centralized and explicit in one place.
locals {
  api_env = {
    DB_BACKEND        = local.aurora_enabled ? "rds_data_api" : "postgres"
    DATABASE_URL      = local.aurora_enabled ? "" : var.database_url
    AWS_REGION        = var.aws_region
    RDS_CLUSTER_ARN   = local.aurora_enabled ? aws_rds_cluster.aurora[0].arn : ""
    RDS_SECRET_ARN    = local.aurora_enabled ? aws_secretsmanager_secret.aurora_master[0].arn : ""
    RDS_DATABASE_NAME = local.aurora_enabled ? var.aurora_database_name : ""
    OPENROUTER_API_KEY  = var.openrouter_api_key
    OPENROUTER_BASE_URL = var.openrouter_base_url
    STATS_SECRET      = var.stats_secret
  }
}
