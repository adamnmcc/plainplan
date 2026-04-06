data "aws_caller_identity" "current" {}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_acm_certificate" "website" {
  count    = local.website_domain_enabled ? 1 : 0
  provider = aws.us_east_1

  domain_name       = local.website_domain_name
  validation_method = "DNS"

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "website_cert_validation" {
  for_each = {
    for dvo in(local.website_domain_enabled ? aws_acm_certificate.website[0].domain_validation_options : []) :
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

resource "aws_acm_certificate_validation" "website" {
  count    = local.website_domain_enabled ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.website[0].arn
  validation_record_fqdns = [for r in aws_route53_record.website_cert_validation : r.fqdn]
}

resource "aws_s3_bucket" "website" {
  count = local.website_domain_enabled ? 1 : 0

  bucket = "${local.name_prefix}-website-${data.aws_caller_identity.current.account_id}"

  tags = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  count = local.website_domain_enabled ? 1 : 0

  bucket = aws_s3_bucket.website[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  count = local.website_domain_enabled ? 1 : 0

  bucket = aws_s3_bucket.website[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "website" {
  count = local.website_domain_enabled ? 1 : 0

  name                              = "${local.name_prefix}-website-oac"
  description                       = "Origin access control for website bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "website_rewrite" {
  count   = local.website_domain_enabled ? 1 : 0
  name    = "${local.name_prefix}-website-rewrite"
  runtime = "cloudfront-js-1.0"
  publish = true
  comment = "Rewrite extensionless website routes to static objects"
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      if (uri === "/") {
        request.uri = "/index.html";
        return request;
      }

      if (uri.endsWith("/")) {
        request.uri = uri + "index.html";
        return request;
      }

      if (!uri.includes(".")) {
        request.uri = uri + ".html";
      }

      return request;
    }
  EOT
}

resource "aws_cloudfront_distribution" "website" {
  count = local.website_domain_enabled ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100"
  aliases             = [local.website_domain_name]
  default_root_object = "index.html"
  wait_for_deployment = false

  origin {
    domain_name              = aws_s3_bucket.website[0].bucket_regional_domain_name
    origin_id                = "website-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.website[0].id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
    target_origin_id       = "website-s3"
    viewer_protocol_policy = "redirect-to-https"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.website_rewrite[0].arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.website[0].certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  tags = local.common_tags
}

data "aws_iam_policy_document" "website_bucket" {
  count = local.website_domain_enabled ? 1 : 0

  statement {
    sid     = "AllowCloudFrontRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.website[0].arn}/*",
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.website[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "website" {
  count = local.website_domain_enabled ? 1 : 0

  bucket = aws_s3_bucket.website[0].id
  policy = data.aws_iam_policy_document.website_bucket[0].json
}

resource "aws_route53_record" "website" {
  count = local.website_domain_enabled ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = local.website_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website[0].domain_name
    zone_id                = aws_cloudfront_distribution.website[0].hosted_zone_id
    evaluate_target_health = false
  }
}

locals {
  website_file_contents = {
    for relpath in fileset("${path.module}/../public", "**") :
    relpath => replace(
      replace(
        replace(
          file("${path.module}/../public/${relpath}"),
          "__WEBSITE_ORIGIN__",
          local.website_origin,
        ),
        "__API_ORIGIN__",
        local.api_origin,
      ),
      "__WEBSITE_HOST__",
      local.website_domain_name,
    )
  }

  website_content_types = {
    ".css"  = "text/css; charset=utf-8"
    ".html" = "text/html; charset=utf-8"
    ".ico"  = "image/x-icon"
    ".jpeg" = "image/jpeg"
    ".jpg"  = "image/jpeg"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".png"  = "image/png"
    ".svg"  = "image/svg+xml"
    ".txt"  = "text/plain; charset=utf-8"
    ".webp" = "image/webp"
    ".xml"  = "application/xml; charset=utf-8"
  }
}

resource "aws_s3_object" "website" {
  for_each = local.website_domain_enabled ? {
    for relpath in fileset("${path.module}/../public", "**") : relpath => relpath
  } : {}

  bucket       = aws_s3_bucket.website[0].id
  key          = each.key
  content      = local.website_file_contents[each.key]
  content_type = lookup(local.website_content_types, regex("\\.[^.]+$", each.key), "application/octet-stream")
  etag         = md5(local.website_file_contents[each.key])

  depends_on = [
    aws_s3_bucket_public_access_block.website,
  ]
}
