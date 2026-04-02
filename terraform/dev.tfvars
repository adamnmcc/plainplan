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

# Custom domain — Terraform creates ACM cert, validates via Route53, and points DNS automatically
custom_domain_name  = "dev.api.plainplan.click"
route53_zone_name   = "plainplan.click"
