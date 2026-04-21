variable "project_prefix" {
  description = "Prefix for all AWS resources"
  type        = string
  default     = "rcoauth2"
}

variable "frontend_base_url" {
  description = "Production frontend URL"
  type        = string
  default     = "https://d2znnfez52b22b.cloudfront.net"
}

variable "cognito_domain_prefix" {
  description = "Cognito Hosted UI domain prefix"
  type        = string
  default     = "rcoauth2-auth"
}

variable "google_client_id" {
  description = "Google OAuth client ID"
  type        = string
}

variable "google_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  sensitive   = true
}
