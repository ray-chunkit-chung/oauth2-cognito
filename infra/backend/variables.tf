variable "project_prefix" {
  description = "Prefix for all AWS resources"
  type        = string
  default     = "rcoauth2"
}

variable "frontend_base_url" {
  description = "Production frontend URL for API CORS"
  type        = string
  default     = "https://d2znnfez52b22b.cloudfront.net"
}

variable "openai_model" {
  description = "OpenAI model name"
  type        = string
  default     = "gpt-5-mini"
}
