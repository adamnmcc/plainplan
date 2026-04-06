locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  hosted_zone_name = var.route53_zone_name != "" ? var.route53_zone_name : var.root_domain_name

  api_domain_name = var.custom_domain_name != "" ? var.custom_domain_name : (
    var.root_domain_name != "" ? (
      var.environment == "prod" ? "api.${var.root_domain_name}" : "${var.environment}.api.${var.root_domain_name}"
    ) : ""
  )

  website_domain_name = var.website_domain_name != "" ? var.website_domain_name : (
    var.root_domain_name != "" ? (
      var.environment == "prod" ? var.root_domain_name : "${var.environment}.${var.root_domain_name}"
    ) : ""
  )

  api_domain_enabled     = local.api_domain_name != "" && local.hosted_zone_name != ""
  website_domain_enabled = local.website_domain_name != "" && local.hosted_zone_name != ""
  website_origin         = local.website_domain_enabled ? "https://${local.website_domain_name}" : ""
  api_origin             = local.api_domain_enabled ? "https://${local.api_domain_name}" : ""
  cors_allow_origins     = distinct(concat(local.website_domain_enabled ? [local.website_origin] : [], var.additional_cors_origins))
  aurora_enabled         = var.enable_aurora_serverless
}
