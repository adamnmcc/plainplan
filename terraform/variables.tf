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

variable "openrouter_api_key" {
  description = "OpenRouter API key"
  type        = string
  sensitive   = true
}

variable "openrouter_base_url" {
  description = "Optional OpenRouter API base URL"
  type        = string
  default     = "https://openrouter.ai/api/v1"
}

variable "stats_secret" {
  description = "Bearer secret for /api/stats"
  type        = string
  sensitive   = true
}

variable "custom_domain_name" {
  description = "Optional custom API domain (example: api.plainplan.click)"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "Optional ACM certificate ARN for custom domain"
  type        = string
  default     = ""
}
