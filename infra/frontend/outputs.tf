output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (used for cache invalidation)"
  value       = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "s3_bucket_name" {
  description = "S3 bucket name for frontend assets"
  value       = aws_s3_bucket.frontend.id
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID"
  value       = aws_cognito_user_pool.frontend.id
}

output "cognito_user_pool_client_id" {
  description = "Cognito user pool app client ID for SPA"
  value       = aws_cognito_user_pool_client.spa.id
}

output "cognito_hosted_ui_domain" {
  description = "Cognito Hosted UI domain"
  value       = "${aws_cognito_user_pool_domain.frontend.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}
