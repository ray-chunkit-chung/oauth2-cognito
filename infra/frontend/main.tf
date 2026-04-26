# ------------------------------------------------------------------------------
# S3 Bucket — static site hosting
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "frontend" {
  # Private origin bucket for static frontend artifacts.
  bucket = "${var.project_prefix}-static"
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  # Keep bucket fully private; CloudFront OAC is the only read path.
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# CloudFront Origin Access Control
# ------------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "frontend" {
  # Sign origin requests so S3 can trust reads only from this distribution.
  name                              = "${var.project_prefix}-frontend-oac-v2"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ------------------------------------------------------------------------------
# CloudFront Function — map extensionless routes to static export files
# ------------------------------------------------------------------------------
resource "aws_cloudfront_function" "frontend_rewrite" {
  # Normalize pretty URLs ("/login") to exported static files ("/login.html").
  name    = "${var.project_prefix}-frontend-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Allow only custom domains, redirect apex to www, and rewrite static routes"
  publish = true

  code = <<-EOT
    function buildQueryString(querystring) {
      var pairs = [];

      for (var key in querystring) {
        if (!Object.prototype.hasOwnProperty.call(querystring, key)) {
          continue;
        }

        var field = querystring[key];

        if (field.multiValue && field.multiValue.length > 0) {
          for (var i = 0; i < field.multiValue.length; i++) {
            var multi = field.multiValue[i];
            pairs.push(multi.value && multi.value.length > 0 ? key + '=' + multi.value : key);
          }
          continue;
        }

        pairs.push(field.value && field.value.length > 0 ? key + '=' + field.value : key);
      }

      return pairs.join('&');
    }

    function handler(event) {
      var request = event.request;
      var uri = request.uri;
      var host = request.headers.host && request.headers.host.value
        ? request.headers.host.value.toLowerCase()
        : '';

      var rootDomain = '${var.frontend_root_domain}';
      var wwwDomain = '${var.frontend_www_domain}';

      if (host !== rootDomain && host !== wwwDomain) {
        // Block default CloudFront hostname and any unexpected host header.
        return {
          statusCode: 403,
          statusDescription: 'Forbidden'
        };
      }

      if (host === rootDomain) {
        // Canonicalize all apex requests to www.
        var target = 'https://' + wwwDomain + uri;
        var query = buildQueryString(request.querystring || {});

        if (query.length > 0) {
          target += '?' + query;
        }

        return {
          statusCode: 301,
          statusDescription: 'Moved Permanently',
          headers: {
            location: { value: target }
          }
        };
      }

      if (uri.endsWith('/')) {
        // Map directory routes to index documents for static hosting.
        request.uri = uri + 'index.html';
        return request;
      }

      if (uri.indexOf('.') === -1) {
        // Add .html for extensionless routes emitted by Next.js static export.
        request.uri = uri + '.html';
      }

      return request;
    }
  EOT
}

# ------------------------------------------------------------------------------
# CloudFront Distribution
# ------------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${var.project_prefix} frontend"
  aliases             = [var.frontend_root_domain, var.frontend_www_domain]

  origin {
    # S3 stays private; CloudFront reaches it with OAC-signed requests.
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed CachingOptimized for static assets.

    function_association {
      # Rewrite happens before cache lookup so normalized paths cache consistently.
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.frontend_rewrite.arn
    }
  }

  # SPA fallback: map missing/forbidden object lookups to the app shell.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Wiring to domain.tf:
    # - domain.tf creates and validates the ACM cert in us-east-1.
    # - this distribution consumes that validated cert ARN for HTTPS on custom domains.
    acm_certificate_arn      = aws_acm_certificate_validation.frontend_custom.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# ------------------------------------------------------------------------------
# S3 Bucket Policy — allow CloudFront OAC only
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "frontend" {
  # Allow object reads only when the request originates from this distribution ARN.
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOAC"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Cognito User Pool + Google Identity Provider (OAuth2)
# ------------------------------------------------------------------------------
resource "aws_cognito_user_pool" "frontend" {
  # User directory for social login identities used by the SPA.
  name = "${var.project_prefix}-user-pool"

  auto_verified_attributes = ["email"]
  alias_attributes         = ["email"]
}

resource "aws_cognito_identity_provider" "google" {
  # Federate Google accounts into Cognito so app auth is standardized.
  user_pool_id  = aws_cognito_user_pool.frontend.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    authorize_scopes = "openid email profile"
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
  }

  attribute_mapping = {
    email    = "email"
    name     = "name"
    picture  = "picture"
    username = "sub"
  }
}

resource "aws_cognito_user_pool_domain" "frontend" {
  # Hosted UI domain for OAuth authorize/token flows.
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.frontend.id
}

resource "aws_cognito_user_pool_client" "spa" {
  # Public SPA client uses Authorization Code + PKCE (no client secret).
  name         = "${var.project_prefix}-spa-client"
  user_pool_id = aws_cognito_user_pool.frontend.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["Google"]

  callback_urls = [
    # Redirect target where the frontend exchanges the auth code.
    "${var.frontend_base_url}/auth/callback",
  ]

  logout_urls = [
    var.frontend_base_url,
  ]

  prevent_user_existence_errors = "ENABLED"
  # Use balanced token lifetimes: UX-friendly sessions with limited token exposure.

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Ensure Google IdP exists before client references supported providers.
  depends_on = [aws_cognito_identity_provider.google]
}

# ------------------------------------------------------------------------------
# SSM Parameters — used by CI/CD deploy step
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "cloudfront_distribution_id" {
  # CI/CD reads this to invalidate the correct distribution after deploy.
  name  = "/${var.project_prefix}/frontend/cloudfront-distribution-id"
  type  = "String"
  value = aws_cloudfront_distribution.frontend.id
}

resource "aws_ssm_parameter" "s3_bucket_name" {
  # CI/CD reads this to upload static build artifacts to the right bucket.
  name  = "/${var.project_prefix}/frontend/s3-bucket-name"
  type  = "String"
  value = aws_s3_bucket.frontend.id
}

resource "aws_ssm_parameter" "frontend_base_url" {
  # Canonical frontend URL for auth redirects and frontend build configuration.
  # Keep this aligned with var.frontend_www_domain/domain records in domain.tf.
  name  = "/${var.project_prefix}/frontend/frontend-base-url"
  type  = "String"
  value = var.frontend_base_url
}

resource "aws_ssm_parameter" "cognito_user_pool_id" {
  # Exposed for frontend config generation during deployment.
  name  = "/${var.project_prefix}/frontend/cognito-user-pool-id"
  type  = "String"
  value = aws_cognito_user_pool.frontend.id
}

resource "aws_ssm_parameter" "cognito_user_pool_client_id" {
  # Exposed for frontend config generation during deployment.
  name  = "/${var.project_prefix}/frontend/cognito-user-pool-client-id"
  type  = "String"
  value = aws_cognito_user_pool_client.spa.id
}

resource "aws_ssm_parameter" "cognito_hosted_ui_domain" {
  # Exposed so the app can build Cognito Hosted UI authorize/logout URLs.
  # This is Cognito's domain prefix output, not the app custom domain in domain.tf.
  name  = "/${var.project_prefix}/frontend/cognito-hosted-ui-domain"
  type  = "String"
  value = aws_cognito_user_pool_domain.frontend.domain
}
