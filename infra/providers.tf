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
    role_arn     = local.dns_role_arn
    session_name = data.aws_caller_identity.current_account.user_id
    tags = {
      username       = data.aws_caller_identity.current_account.user_id
      username_lower = lower(data.aws_caller_identity.current_account.user_id)
    }
  }
}

data "aws_caller_identity" "second" {
  provider = aws.dns
}

