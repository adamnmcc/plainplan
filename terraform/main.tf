locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  custom_domain_enabled = var.custom_domain_name != "" && var.route53_zone_name != ""
  aurora_enabled        = var.enable_aurora_serverless
}
