variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_prefix" {
  description = "Prefix for all AWS resources"
  type        = string
  default     = "rcoauth2"
}
