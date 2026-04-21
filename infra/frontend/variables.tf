variable "project_prefix" {
  description = "Prefix for all AWS resources"
  type        = string
  default     = "rcoauth2"
}

variable "frontend_base_url" {
  description = "Production frontend URL"
  type        = string
  default     = "https://ray-chunkit-chung.click"
}

variable "frontend_local_base_url" {
  description = "Local frontend URL"
  type        = string
  default     = "http://localhost:3000"
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
