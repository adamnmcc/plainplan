project_name      = "plainplan"
environment       = "dev"
aws_region        = "eu-west-1"
lambda_zip_path   = "../build/plainplan-lambda.zip"

# RDS free-tier PostgreSQL (db.t4g.micro). Set enable_aurora_serverless = true to use Aurora Serverless v2 instead.
enable_aurora_serverless = false
rds_database_name       = "plainplan"
rds_engine_version      = "16.4"

# Custom domain — Terraform creates ACM cert, validates via Route53, and points DNS automatically
custom_domain_name  = "dev.api.plainplan.click"
route53_zone_name   = "plainplan.click"
