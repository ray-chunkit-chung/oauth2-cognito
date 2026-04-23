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
    key    = "frontend/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

provider "aws" {}

provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}

data "aws_region" "current" {}
