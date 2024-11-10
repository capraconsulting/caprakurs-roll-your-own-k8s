terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = "1.7.5"
}

# Configure the AWS Provider
provider "aws" {
  alias  = "default"
  region = "eu-west-1"
}
provider "aws" {
  alias  = "dns"
  region = "eu-west-1"

  assume_role {
    role_arn = "arn:aws:iam::859141738257:role/dns-mangement-for-kurs-bews"
  }
}

data "aws_caller_identity" "second" {
  provider = aws.dns
}

