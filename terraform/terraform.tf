terraform {
  required_version = "~> 1.10.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.88.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7.0"
    }

  }
  backend "s3" {
    bucket         = "terraform-state-bucket-rc-tl-2025"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}