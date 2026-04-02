project_name      = "plainplan"
environment       = "dev"
aws_region        = "eu-west-1"
lambda_zip_path   = "../build/plainplan-lambda.zip"

# Aurora is the default deployment path. Leave database_url empty unless you are intentionally using external Postgres.
database_url      = ""
enable_aurora_serverless = true
aurora_database_name     = "plainplan"
aurora_engine_version    = "16.4"
aurora_min_capacity      = 0.5
aurora_max_capacity      = 1

# Optional custom domain setup
custom_domain_name = "dev.api.plainplan.click"
acm_certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
