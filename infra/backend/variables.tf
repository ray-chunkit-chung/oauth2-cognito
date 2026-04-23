variable "project_prefix" {
  description = "Prefix for all AWS resources"
  type        = string
  default     = "rcoauth2"
}

variable "frontend_base_url" {
  description = "Production frontend URL for API CORS"
  type        = string
  default     = "https://www.ray-chunkit-chung.click"
}

variable "openai_model" {
  description = "OpenAI model name"
  type        = string
  default     = "gpt-5-mini"
}

variable "enable_lambda_warmup" {
  description = "Enable EventBridge schedule that periodically warms the chat Lambda"
  type        = bool
  default     = true
}

variable "lambda_warmup_interval_minutes" {
  description = "Warmup interval in minutes for the chat Lambda"
  type        = number
  default     = 5
}
