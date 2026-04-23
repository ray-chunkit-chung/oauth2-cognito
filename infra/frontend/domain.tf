data "aws_route53_zone" "frontend" {
  name         = "${var.frontend_root_domain}."
  private_zone = false
}

resource "aws_acm_certificate" "frontend_custom" {
  provider = aws.use1

  domain_name               = var.frontend_www_domain
  subject_alternative_names = [var.frontend_root_domain]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "frontend_cert_validation" {
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
  provider = aws.use1

  certificate_arn         = aws_acm_certificate.frontend_custom.arn
  validation_record_fqdns = [for record in aws_route53_record.frontend_cert_validation : record.fqdn]
}

resource "aws_route53_record" "frontend_www_a" {
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
  zone_id = data.aws_route53_zone.frontend.zone_id
  name    = var.frontend_root_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}