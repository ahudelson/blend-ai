provider "aws" {
  region  = var.region
  profile = var.aws_cli_profile
}

provider "aws" {
  alias   = "acm"
  region  = "us-east-1"  # ACM certs for CloudFront must be in us-east-1
  profile = var.aws_cli_profile
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}