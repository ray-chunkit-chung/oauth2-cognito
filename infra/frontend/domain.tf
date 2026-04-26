# Domain + certificate layer for the frontend.
#
# What this file owns:
# - Route53 hosted zone lookup for your public domain.
# - ACM certificate issuance/validation for CloudFront HTTPS.
# - Route53 alias records (apex + www) pointing to CloudFront.
#
# How this wires to main.tf:
# - main.tf -> aws_cloudfront_distribution.frontend.viewer_certificate
#   uses aws_acm_certificate_validation.frontend_custom.certificate_arn from this file.
# - this file -> aws_route53_record frontend_* alias blocks
#   target aws_cloudfront_distribution.frontend.* created in main.tf.

data "aws_route53_zone" "frontend" {
  # Look up the existing public hosted zone.
  # Terraform does NOT create the zone here; it must already exist in Route53.
  name         = "${var.frontend_root_domain}."
  private_zone = false
}

resource "aws_acm_certificate" "frontend_custom" {
  # CloudFront requires viewer certificates in us-east-1, so this uses provider alias aws.use1.
  provider = aws.use1

  # Primary cert name is the canonical www domain, with apex as SAN.
  domain_name               = var.frontend_www_domain
  subject_alternative_names = [var.frontend_root_domain]
  validation_method         = "DNS"

  lifecycle {
    # Keep old cert valid until replacement cert is issued/validated to avoid HTTPS downtime.
    create_before_destroy = true
  }
}

resource "aws_route53_record" "frontend_cert_validation" {
  # Create DNS validation records from ACM-generated domain validation options.
  # ACM checks these records before cert status becomes ISSUED.
  for_each = {
    for dvo in aws_acm_certificate.frontend_custom.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.frontend.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "frontend_custom" {
  # Wait until DNS validation succeeds, then expose a validated certificate ARN.
  # main.tf consumes this ARN in CloudFront viewer_certificate.
  provider = aws.use1

  certificate_arn         = aws_acm_certificate.frontend_custom.arn
  validation_record_fqdns = [for record in aws_route53_record.frontend_cert_validation : record.fqdn]
}

resource "aws_route53_record" "frontend_www_a" {
  # IPv4 alias: www -> CloudFront distribution from main.tf.
  zone_id = data.aws_route53_zone.frontend.zone_id
  name    = var.frontend_www_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "frontend_www_aaaa" {
  # IPv6 alias: www -> CloudFront distribution from main.tf.
  zone_id = data.aws_route53_zone.frontend.zone_id
  name    = var.frontend_www_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "frontend_apex_a" {
  # IPv4 alias: apex/root domain -> same CloudFront distribution.
  # Redirect behavior (apex -> www) is enforced by CloudFront Function in main.tf.
  zone_id = data.aws_route53_zone.frontend.zone_id
  name    = var.frontend_root_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "frontend_apex_aaaa" {
  # IPv6 alias: apex/root domain -> same CloudFront distribution.
  zone_id = data.aws_route53_zone.frontend.zone_id
  name    = var.frontend_root_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}