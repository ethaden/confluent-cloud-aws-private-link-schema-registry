terraform {
  required_providers {
    confluent = {
      source = "confluentinc/confluent"
      #version = "2.00.0"
    }
    aws = {
        source = "hashicorp/aws"
    }
  }
}

provider "confluent" {
  cloud_api_key    = local.confluent_creds.api_key
  cloud_api_secret = local.confluent_creds.api_secret
}

provider "aws" {
    region = var.aws_region

    default_tags {
      tags = local.confluent_tags
    }
}
