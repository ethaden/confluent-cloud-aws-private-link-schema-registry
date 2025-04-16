# Here we set up another environment in a different region, another cluster (just a basic one) 
# and two private links for serverless products in that other region, one for the original environment and one for the additional one

resource "confluent_environment" "cc_env_other" {
  display_name = var.ccloud_environment_name_other

  stream_governance {
    package = "ESSENTIALS"
  }

  lifecycle {
    prevent_destroy = false
  }
}

data "confluent_schema_registry_cluster" "cc_env_schema_registry_other" {
    environment {
      id = confluent_environment.cc_env_other.id
    }
    # Using this dependency avoids a potential race condition where the schema registry is still created while terraform already tries to access it (which will fail)
    depends_on = [ 
        confluent_kafka_cluster.cc_cluster_other_region_other_environment,
        confluent_kafka_cluster.cc_cluster_original_region_other_environment,
        confluent_private_link_attachment_connection.private_link_serverless_original_region_other_env,
        confluent_private_link_attachment_connection.private_link_serverless_other_region_other_env
    ]
}

# This cluster is created solely for triggering the creation of a Schema Registry instance in the other region
resource "confluent_kafka_cluster" "cc_cluster_other_region_other_environment" {
  display_name = var.ccloud_cluster_name_other
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = var.aws_region_other
  # For cost reasons, we use a basic cluster by default. However, you can choose a different type by setting the variable ccloud_cluster_type
  basic {}

  environment {
    id = confluent_environment.cc_env_other.id
  }

  lifecycle {
    prevent_destroy = false
  }
  # We need to add a dependency to the main cluster.
  # Otherwise, the Schema Registry instance might be spawned in var.aws_region_other if this cluster "wins the race" and is spawned first
  depends_on = [ confluent_kafka_cluster.cc_cluster ]
}

# Currently, the Confluent Terraform provider does not support IP Filtering, only the REST API does.
# Thus, just for this demo, we use generic REST calls instead (TBD)
# IP group "ipg-none" is pre-defined and includes all IPv4 IP addresses.
resource "restapi_object" "ip_filter_schema_registry_other_env" {
  path = "/iam/v2/ip-filters"
  data = "${jsonencode(
    {
        "api_version" = "iam/v2",
        "kind" = "IpFilter",
        "filter_name" = "${var.resource_prefix}_Block_Public_Access_Schema_Registry_Other_region",
        "resource_group" = "multiple",
        "resource_scope" = "crn://confluent.cloud/organization=${data.confluent_organization.cc_org.id}/environment=${confluent_environment.cc_env_other.id}",
        "operation_groups" = ["SCHEMA"],
        "ip_groups" = [
        {"id" = "ipg-none"}
        ]
    })}"
}

# Serverless Private Link in the other AWS region to the other Confluent Cloud environment

resource "aws_security_group" "private_link_serverless_other_region_other_env" {
  name        = "${local.resource_prefix}_private_link_serverless_other_region_other_env"
  vpc_id      = aws_vpc.aws_vpc_other.id
  provider = aws.aws_region_other

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

# Create a private link attachment in order to get private endpoints for Schema Registry later-on
resource "confluent_private_link_attachment" "private_link_serverless_other_region_other_env" {
  cloud = "AWS"
  region = var.aws_region_other
  display_name = "${local.resource_prefix}_private_link_serverless_other_region_other_env"
  environment {
    id = confluent_environment.cc_env_other.id
  }
}

resource "aws_vpc_endpoint" "private_link_serverless_other_region_other_env" {
  vpc_id            = aws_vpc.aws_vpc_other.id
  service_name      =  confluent_private_link_attachment.private_link_serverless_other_region_other_env.aws[0].vpc_endpoint_service_name
  vpc_endpoint_type = "Interface"
  provider = aws.aws_region_other

  security_group_ids = [
    aws_security_group.private_link_serverless_other_region_other_env.id,
  ]
  tags = {
      Name = "${var.resource_prefix}_private_link_serverless_other_region_other_env"
  }

  subnet_ids          = [for index in [0,1,2]: aws_subnet.public_subnets_other[index].id]
  # Only for AWS and AWS Marketplace partner services. We configure our own hosted zone instead
  private_dns_enabled = false
}

# Set up a private link connection in Confluent Cloud, which connects the private endpoint to the private link attachment
resource "confluent_private_link_attachment_connection" "private_link_serverless_other_region_other_env" {
  display_name ="${local.resource_prefix}_platt_original_region_other_env"
  environment {
    id = confluent_environment.cc_env_other.id
  }
  aws {
    vpc_endpoint_id = aws_vpc_endpoint.private_link_serverless_other_region_other_env.id
  }
  private_link_attachment {
    id = confluent_private_link_attachment.private_link_serverless_other_region_other_env.id
  }
}

# This cluster is only required for initiating the Confluent-internal connectivity to the Schema Registry
# AWS Region: original one
# Environment: other environment
# We need this for demonstrating Schema Linking to a Schema Registry instance hosted in another environment and another region
# Note: This will trigger creation of a private endpoint in our original region
resource "confluent_kafka_cluster" "cc_cluster_original_region_other_environment" {
  display_name = "${var.ccloud_cluster_name_other}_sr_ep_original_region"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = var.aws_region
  # For cost reasons, we use a basic cluster by default. However, you can choose a different type by setting the variable ccloud_cluster_type
  basic {}

  environment {
    id = confluent_environment.cc_env_other.id
  }

  lifecycle {
    prevent_destroy = false
  }
  # We need to add a dependency to the main cluster.
  # Otherwise, the Schema Registry instance might be spawned in var.aws_region_other if this cluster "wins the race" and is spawned first
  depends_on = [ 
    confluent_kafka_cluster.cc_cluster,
    confluent_kafka_cluster.cc_cluster_other_region_other_environment 
  ]
}


# Private Link serverless connection to the other environment from our original region
# This is required for Schema Linking from our original SR instance in our original region to the other SR instance (in the other environment) in the other region

resource "aws_security_group" "private_link_serverless_original_region_other_env" {
  name        = "${local.resource_prefix}_private_link_serverless_original_region_other_env"
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

resource "confluent_private_link_attachment" "private_link_serverless_original_region_other_env" {
  cloud = "AWS"
  region = var.aws_region
  display_name = "${local.resource_prefix}_private_link_serverless_original_region_other_env"
  environment {
    id = confluent_environment.cc_env_other.id
  }
}

resource "aws_vpc_endpoint" "private_link_serverless_original_region_other_env" {
  vpc_id            = data.aws_vpc.vpc.id
  service_name      =  confluent_private_link_attachment.private_link_serverless_original_region_other_env.aws[0].vpc_endpoint_service_name
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.private_link_serverless_original_region_other_env.id,
  ]
  tags = {
      Name = "${var.resource_prefix}_private_link_serverless_original_region_other_env"
  }

  subnet_ids          = data.aws_subnets.vpc_subnets.ids
  # Only for AWS and AWS Marketplace partner services. We configure our own hosted zone instead
  private_dns_enabled = false
}

# Set up a private link connection in Confluent Cloud, which connects the private endpoint to the private link attachment
resource "confluent_private_link_attachment_connection" "private_link_serverless_original_region_other_env" {
  display_name ="${local.resource_prefix}_platt_original_region_other_env"
  environment {
    id = confluent_environment.cc_env_other.id
  }
  aws {
    vpc_endpoint_id = aws_vpc_endpoint.private_link_serverless_original_region_other_env.id
  }
  private_link_attachment {
    id = confluent_private_link_attachment.private_link_serverless_original_region_other_env.id
  }
}

# We use the hosted zones we created before for the VPCs here and add just another specific record for the respective other schema registry to both of them
# Make SR of second environment (located in the other AWS region) available in the main AWS region
resource "aws_route53_record" "private_link_serverless_vpc_two_schema_registry_original_env" {
  zone_id = aws_route53_zone.private_link_serverless_vpc_two_other_region.zone_id
  provider = aws.aws_region_other
  name    = replace(data.confluent_schema_registry_cluster.cc_env_schema_registry.private_regional_rest_endpoints[var.aws_region_other],
                "https://", "")
  type    = "CNAME"
  ttl     = "60"
  records = [
    aws_vpc_endpoint.private_link_serverless_other_region_original_env.dns_entry[0].dns_name
  ]
}

# Make SR of second environment (located in the other AWS region) available in the main AWS region
resource "aws_route53_record" "private_link_serverless_vpc_one_schema_registry_other_env" {
  zone_id = aws_route53_zone.private_link_serverless_vpc_one_original_region.zone_id
  #name    = "*.${aws_route53_zone.private_link_serverless_other_env.name}"
  name    = replace(data.confluent_schema_registry_cluster.cc_env_schema_registry_other.private_regional_rest_endpoints[var.aws_region],
                "https://", "")
  type    = "CNAME"
  ttl     = "60"
  records = [
    aws_vpc_endpoint.private_link_serverless_original_region_other_env.dns_entry[0].dns_name
  ]
}

output "cc_other_environment_id" {
    value = confluent_environment.cc_env_other.id
}

output "schema_registry_private_endpoint_original_region_other_env" {
    value = data.confluent_schema_registry_cluster.cc_env_schema_registry_other.private_regional_rest_endpoints[var.aws_region]
}

output "schema_registry_private_endpoint_other_region_other_env" {
  value = data.confluent_schema_registry_cluster.cc_env_schema_registry_other.private_regional_rest_endpoints[var.aws_region_other]
  # We need to delay the execution of the above statement slightly by adding dependencies, otherwise the private regional endpoint
  # for the schema registry instance for the "aws.aws_region_other" might not be available yet (as it is still provisioning)
}

output "schema_registry_other_env_id" {
    value = data.confluent_schema_registry_cluster.cc_env_schema_registry_other.id
}
