variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_prefix" {
  description = "Prefix for all AWS resources"
  type        = string
  default     = "rcoauth2"
}
