project_name     = "plainplan"
environment      = "prod"
aws_region       = "eu-west-1"
lambda_zip_path  = "../build/plainplan-lambda.zip"
root_domain_name = "plainplan.click"

# RDS free-tier PostgreSQL (db.t4g.micro). Set enable_aurora_serverless = true to use Aurora Serverless v2 instead.
enable_aurora_serverless = false
rds_database_name        = "plainplan"
rds_engine_version       = "18.3"
