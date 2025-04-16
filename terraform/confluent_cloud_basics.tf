# Confluent Cloud Environment

data "confluent_organization" "cc_org" {}

resource "confluent_environment" "cc_env" {
  display_name = var.ccloud_environment_name

  stream_governance {
    package = "ESSENTIALS"
  }

  lifecycle {
    prevent_destroy = false
  }
}

data "confluent_schema_registry_cluster" "cc_env_schema_registry" {
  environment {
    id = confluent_environment.cc_env.id
  }
  # Using this dependency avoids a potential race condition where the schema registry is still created while terraform already tries to access it (which will fail)
  depends_on = [ 
    confluent_kafka_cluster.cc_cluster,
    confluent_kafka_cluster.cc_cluster_other_region_same_environment,
    aws_route53_record.private_link_serverless_vpc_two_other_region_wildcard_record,
    confluent_private_link_attachment_connection.private_link_serverless_other_region_original_env
   ]
}

resource "confluent_service_account" "cc_env_admin" {
  display_name = "${var.resource_prefix}_cc_env_admin"
  description  = "Service Account Environment Admin (just for accessing Schema Registry)"
}

resource "confluent_api_key" "cc_env_schema_registry_env_admin_api_key" {
  display_name = "${var.resource_prefix}_cc_env_schema_registry_cluster_admin_api_key"
  description  = "Schema Registry API Key that is owned by '${var.resource_prefix}_cc_env_admin' service account"
  owner {
    id          = confluent_service_account.cc_env_admin.id
    api_version = confluent_service_account.cc_env_admin.api_version
    kind        = confluent_service_account.cc_env_admin.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.cc_env_schema_registry.id
    api_version = data.confluent_schema_registry_cluster.cc_env_schema_registry.api_version
    kind        = data.confluent_schema_registry_cluster.cc_env_schema_registry.kind

    environment {
      id = confluent_environment.cc_env.id
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_role_binding" "cc_env_schema_registry_env_admin_role_binding" {
  principal   = "User:${confluent_service_account.cc_env_admin.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${data.confluent_schema_registry_cluster.cc_env_schema_registry.resource_name}/subject=*"
}

data "confluent_schema_registry_cluster_config" "cc_env_schema_registry" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.cc_env_schema_registry.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.cc_env_schema_registry.private_regional_rest_endpoints[var.aws_region]
  credentials {
    key    = confluent_api_key.cc_env_schema_registry_cluster_admin_api_key.id
    secret = confluent_api_key.cc_env_schema_registry_cluster_admin_api_key.secret
  }
  depends_on = [ confluent_role_binding.cc_env_schema_registry_env_admin_role_binding ]
}

# Create a private link attachment in Confluent Cloud
resource "confluent_private_link_attachment" "private_link_serverless" {
  cloud = "AWS"
  region = var.aws_region
  display_name = "${local.resource_prefix}_private_link_serverless"
  environment {
    id = confluent_environment.cc_env.id
  }
}

resource "aws_security_group" "private_link_serverless" {
  name        = "${local.resource_prefix}_private_link_serverless"
  vpc_id      = data.aws_vpc.vpc.id

  dynamic "ingress" {
    for_each = { 1 : 80, 2 : 443, 3 : 9092 }
    content {
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      from_port        = ingress.value
      to_port          = ingress.value
    }
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

# Set up a private endpoint in AWS
resource "aws_vpc_endpoint" "private_link_serverless" {
  vpc_id            = var.vpc_id
  service_name      =  confluent_private_link_attachment.private_link_serverless.aws[0].vpc_endpoint_service_name
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.private_link_serverless.id,
  ]
  tags = {
      Name = "${var.resource_prefix}_private_link_serverless"
  }

  subnet_ids          = data.aws_subnets.vpc_subnets.ids
  # Only for AWS and AWS Marketplace partner services. We configure our own hosted zone instead
  private_dns_enabled = false
}

# Set up a private link connection in Confluent Cloud, which connects the private endpoint to the private link attachment
resource "confluent_private_link_attachment_connection" "private_link_serverless" {
  display_name ="${local.resource_prefix}_platt"
  environment {
    id = confluent_environment.cc_env.id
  }
  aws {
    vpc_endpoint_id = aws_vpc_endpoint.private_link_serverless.id
  }
  private_link_attachment {
    id = confluent_private_link_attachment.private_link_serverless.id
  }
}

# DNS for the private link connection to the serverless products (i.e. schema registry)

# First, we create two hosted zones, one per VPC
resource "aws_route53_zone" "private_link_serverless_vpc_one_original_region" {
  name = "${var.aws_region}.aws.private.confluent.cloud"

  vpc {
    vpc_id = data.aws_vpc.vpc.id
  }
}

resource "aws_route53_zone" "private_link_serverless_vpc_two_other_region" {
  name = "${var.aws_region_other}.aws.private.confluent.cloud"
  provider = aws.aws_region_other
  vpc {
    vpc_id = aws_vpc.aws_vpc_other.id
  }
}

resource "aws_route53_record" "private_link_serverless_vpc_one_original_zone_wildcard_record" {
  zone_id = aws_route53_zone.private_link_serverless_vpc_one_original_region.zone_id
  name    = "*.${aws_route53_zone.private_link_serverless_vpc_one_original_region.name}"
  type    = "CNAME"
  ttl     = "60"
  records = [
    aws_vpc_endpoint.private_link_serverless.dns_entry[0].dns_name
  ]
}


output "schema_registry_private_endpoint_original_region_main_env" {
    value = data.confluent_schema_registry_cluster.cc_env_schema_registry.private_regional_rest_endpoints[var.aws_region]
}

output "schema_registry_original_env_id" {
    value = data.confluent_schema_registry_cluster.cc_env_schema_registry.id
}
# The next entries demonstrate how to output the generated API keys to the console even though they are considered to be sensitive data by Terraform
# Uncomment these lines if you want to generate that output
# output "cluster_api_key_admin" {
#     value = nonsensitive("Key: ${confluent_api_key.cc_cluster_admin_api_key.id}\nSecret: ${confluent_api_key.cc_cluster_admin_api_key.secret}")
# }

# output "cluster_api_key_producer" {
#     value = nonsensitive("Key: ${confluent_api_key.cc_cluster_producer_api_key.id}\nSecret: ${confluent_api_key.cc_cluster_producer_api_key.secret}")
# }

# output "cluster_api_key_consumer" {
#     value = nonsensitive("Key: ${confluent_api_key.cc_cluster_consumer_api_key.id}\nSecret: ${confluent_api_key.cc_cluster_consumer_api_key.secret}")
# }

# Currently, the Confluent Terraform provider does not support IP Filtering, only the REST API does.
# Thus, just for this demo, we use generic REST calls instead (TBD)
# IP group "ipg-none" is pre-defined and includes all IPv4 IP addresses.
resource "restapi_object" "ip_filter_schema_registry" {
  path = "/iam/v2/ip-filters"
  data = "${jsonencode(
    {
        "api_version" = "iam/v2",
        "kind" = "IpFilter",
        "filter_name" = "${var.resource_prefix}_Block_Public_Access_Schema_Registry",
        "resource_group" = "multiple",
        "resource_scope" = "crn://confluent.cloud/organization=${data.confluent_organization.cc_org.id}/environment=${confluent_environment.cc_env.id}",
        "operation_groups" = ["SCHEMA"],
        "ip_groups" = [
        {"id" = "ipg-none"}
        ]
    })}"
}

# crn://confluent.cloud/organization=${confluent_organization.cc_org.id}/environment=${confluent_environment.cc_env.id}

output "cc_primary_environment_id" {
    value = confluent_environment.cc_env.id
}
