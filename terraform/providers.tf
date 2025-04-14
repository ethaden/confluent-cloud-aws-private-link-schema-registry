terraform {
  required_providers {
    confluent = {
      source = "confluentinc/confluent"
      #version = "2.00.0"
    }
    aws = {
        source = "hashicorp/aws"
    }
    restapi = {
      source = "Mastercard/restapi"
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

provider "aws" {
  region = var.aws_region_other
  alias = "aws_region_other"

    default_tags {
      tags = local.confluent_tags
    }
}

# Using a generig REST API provider as long as there is no terraform integration for creating and managing certificate authorities
provider "restapi" {
  uri                  = "https://api.confluent.cloud"
  write_returns_object = true
  debug                = true

  #headers = {
  #  "X-Auth-Token" = var.AUTH_TOKEN,
  #  "Content-Type" = "application/json"
  #}
  headers = {
    "Content-Type" = "application/json"
  }

  create_method  = "POST"
  update_method  = "PATCH"
  destroy_method = "DELETE"

  id_attribute = "id"
  username = local.confluent_creds.api_key
  password = local.confluent_creds.api_secret
  rate_limit = 40
}
