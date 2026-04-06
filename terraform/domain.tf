# ---- Route53 zone lookup ----

data "aws_route53_zone" "main" {
  count = local.api_domain_enabled || local.website_domain_enabled ? 1 : 0
  name  = local.hosted_zone_name
}

# ---- API ACM certificate + DNS validation ----

resource "aws_acm_certificate" "api" {
  count = local.api_domain_enabled ? 1 : 0

  domain_name       = local.api_domain_name
  validation_method = "DNS"

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "api_cert_validation" {
  for_each = {
    for dvo in(local.api_domain_enabled ? aws_acm_certificate.api[0].domain_validation_options : []) :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "api" {
  count = local.api_domain_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.api[0].arn
  validation_record_fqdns = [for r in aws_route53_record.api_cert_validation : r.fqdn]
}

# ---- API Gateway custom domain ----

resource "aws_apigatewayv2_domain_name" "custom" {
  count = local.api_domain_enabled ? 1 : 0

  domain_name = local.api_domain_name

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.api[0].certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_api_mapping" "custom" {
  count = local.api_domain_enabled ? 1 : 0

  api_id      = aws_apigatewayv2_api.http.id
  domain_name = aws_apigatewayv2_domain_name.custom[0].id
  stage       = aws_apigatewayv2_stage.default.id
}

# ---- DNS A record pointing API domain to API Gateway ----

resource "aws_route53_record" "api" {
  count = local.api_domain_enabled ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = local.api_domain_name
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.custom[0].domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.custom[0].domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}
