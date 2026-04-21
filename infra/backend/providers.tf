terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "rcoauth2-terraform-state"
    key    = "backend/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

provider "aws" {}

data "aws_region" "current" {}
