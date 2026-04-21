# ------------------------------------------------------------------------------
# S3 Bucket — static site hosting
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_prefix}-static"
}

resource "aws_s3_bucket_public_access_block" "frontend" {
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
  name                              = "${var.project_prefix}-frontend-oac-v2"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ------------------------------------------------------------------------------
# CloudFront Function — map extensionless routes to static export files
# ------------------------------------------------------------------------------
resource "aws_cloudfront_function" "frontend_rewrite" {
  name    = "${var.project_prefix}-frontend-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite extensionless paths to static export HTML files"
  publish = true

  code = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
        return request;
      }

      if (uri.indexOf('.') === -1) {
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
  default_root_object = "index.html"
  comment             = "${var.project_prefix} frontend"

  origin {
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

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed CachingOptimized

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.frontend_rewrite.arn
    }
  }

  # SPA fallback — serve index.html for client-side routing
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
    cloudfront_default_certificate = true
  }
}

# ------------------------------------------------------------------------------
# S3 Bucket Policy — allow CloudFront OAC only
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "frontend" {
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
  name = "${var.project_prefix}-user-pool"

  auto_verified_attributes = ["email"]
  alias_attributes         = ["email"]
}

resource "aws_cognito_identity_provider" "google" {
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
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.frontend.id
}

resource "aws_cognito_user_pool_client" "spa" {
  name         = "${var.project_prefix}-spa-client"
  user_pool_id = aws_cognito_user_pool.frontend.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["Google"]

  callback_urls = [
    "${var.frontend_base_url}/auth/callback",
  ]

  logout_urls = [
    var.frontend_base_url,
  ]

  prevent_user_existence_errors = "ENABLED"

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  depends_on = [aws_cognito_identity_provider.google]
}

# ------------------------------------------------------------------------------
# SSM Parameters — used by CI/CD deploy step
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "cloudfront_distribution_id" {
  name  = "/${var.project_prefix}/frontend/cloudfront-distribution-id"
  type  = "String"
  value = aws_cloudfront_distribution.frontend.id
}

resource "aws_ssm_parameter" "s3_bucket_name" {
  name  = "/${var.project_prefix}/frontend/s3-bucket-name"
  type  = "String"
  value = aws_s3_bucket.frontend.id
}

resource "aws_ssm_parameter" "cognito_user_pool_id" {
  name  = "/${var.project_prefix}/frontend/cognito-user-pool-id"
  type  = "String"
  value = aws_cognito_user_pool.frontend.id
}

resource "aws_ssm_parameter" "cognito_user_pool_client_id" {
  name  = "/${var.project_prefix}/frontend/cognito-user-pool-client-id"
  type  = "String"
  value = aws_cognito_user_pool_client.spa.id
}

resource "aws_ssm_parameter" "cognito_hosted_ui_domain" {
  name  = "/${var.project_prefix}/frontend/cognito-hosted-ui-domain"
  type  = "String"
  value = aws_cognito_user_pool_domain.frontend.domain
}
