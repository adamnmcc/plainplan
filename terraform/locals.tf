# Keep app settings centralized and explicit in one place.
locals {
  api_env = merge(
    {
      DB_BACKEND          = local.aurora_enabled ? "rds_data_api" : "postgres"
      OPENROUTER_API_KEY  = local.secret_openrouter_api_key
      OPENROUTER_BASE_URL = local.secret_openrouter_base_url
      STATS_SECRET        = local.secret_stats_secret
    },
    local.aurora_enabled ? {
      DATABASE_URL      = ""
      RDS_CLUSTER_ARN   = aws_rds_cluster.aurora[0].arn
      RDS_SECRET_ARN    = aws_secretsmanager_secret.aurora_master[0].arn
      RDS_DATABASE_NAME = var.aurora_database_name
    } : {
      DATABASE_URL      = local.rds_database_url
      RDS_CLUSTER_ARN   = ""
      RDS_SECRET_ARN    = ""
      RDS_DATABASE_NAME = ""
    },
  )
}
