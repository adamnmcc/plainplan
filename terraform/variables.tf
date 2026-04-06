variable "project_name" {
  description = "Project/service name used in resource naming"
  type        = string
  default     = "plainplan"
}

variable "environment" {
  description = "Deployment environment label"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "root_domain_name" {
  description = "Root DNS zone for website and API hostnames (example: plainplan.click). Dev derives dev.plainplan.click and dev.api.plainplan.click; prod derives plainplan.click and api.plainplan.click."
  type        = string
  default     = ""
}

variable "lambda_zip_path" {
  description = "Path to Lambda deployment zip"
  type        = string
  default     = "../build/plainplan-lambda.zip"
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "database_url" {
  description = "External PostgreSQL connection string. Leave empty for the default Aurora deployment path."
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_aurora_serverless" {
  description = "Provision Aurora Serverless v2 and use the RDS Data API. Set false only if you want to fall back to an external DATABASE_URL."
  type        = bool
  default     = true
}

variable "aurora_database_name" {
  description = "Initial database name for Aurora Serverless"
  type        = string
  default     = "plainplan"
}

variable "aurora_master_username" {
  description = "Master username for Aurora Serverless"
  type        = string
  default     = "plainplan_admin"
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

variable "aurora_min_capacity" {
  description = "Aurora Serverless v2 minimum ACUs. Aurora does not scale to zero. 0.5 is the lowest setting."
  type        = number
  default     = 0.5
}

variable "aurora_max_capacity" {
  description = "Aurora Serverless v2 maximum ACUs"
  type        = number
  default     = 1
}

# ---- RDS free-tier Postgres (when enable_aurora_serverless = false) ----

variable "rds_database_name" {
  description = "Database name for the RDS PostgreSQL instance"
  type        = string
  default     = "plainplan"
}

variable "rds_master_username" {
  description = "Master username for the RDS PostgreSQL instance"
  type        = string
  default     = "plainplan_admin"
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version for RDS"
  type        = string
  default     = "18.3"
}

# openrouter_api_key, openrouter_base_url, stats_secret are read
# directly from Secrets Manager by Terraform (see config_secrets.tf).

variable "custom_domain_name" {
  description = "Optional API domain override. When unset, Terraform derives the API domain from root_domain_name and environment."
  type        = string
  default     = ""
}

variable "website_domain_name" {
  description = "Optional website domain override. When unset, Terraform derives the website domain from root_domain_name and environment."
  type        = string
  default     = ""
}

variable "route53_zone_name" {
  description = "Optional Route53 hosted zone name override. Defaults to root_domain_name when omitted."
  type        = string
  default     = ""
}

variable "additional_cors_origins" {
  description = "Additional browser origins allowed to call the API."
  type        = list(string)
  default     = []
}
