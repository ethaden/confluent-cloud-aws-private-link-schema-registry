# This cluster is only required for initiating the Confluent-internal connectivity to the Schema Registry
# AWS Region: other region
# Environment: original environment
# Note: This will trigger creation of a private endpoint in the other region
resource "confluent_kafka_cluster" "cc_cluster_other_region_same_environment" {
  display_name = "${var.ccloud_cluster_name_other}_sr_ep_other_region"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = var.aws_region_other
  # For cost reasons, we use a basic cluster by default. However, you can choose a different type by setting the variable ccloud_cluster_type
  basic {}

  environment {
    id = confluent_environment.cc_env.id
  }

  lifecycle {
    prevent_destroy = false
  }
  # We need to add a dependency to the main cluster.
  # Otherwise, the Schema Registry instance might be spawned in var.aws_region_other if this cluster "wins the race" and is spawned first
  depends_on = [ confluent_kafka_cluster.cc_cluster ]
}


# Confluent Cloud Private Link

# Create a private link attachment in Confluent Cloud
resource "confluent_private_link_attachment" "private_link_serverless_other_region_original_env" {
  cloud = "AWS"
  region = var.aws_region_other
  display_name = "${local.resource_prefix}_private_link_serverless_other_region_original_env"
  environment {
    id = confluent_environment.cc_env.id
  }
}

resource "aws_security_group" "private_link_serverless_other_region_original_env" {
  name        = "${local.resource_prefix}_private_link_serverless_other_region_original_env"
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

# Set up a private endpoint in AWS
resource "aws_vpc_endpoint" "private_link_serverless_other_region_original_env" {
  vpc_id            = aws_vpc.aws_vpc_other.id
  service_name      =  confluent_private_link_attachment.private_link_serverless_other_region_original_env.aws[0].vpc_endpoint_service_name
  vpc_endpoint_type = "Interface"
  provider = aws.aws_region_other

  security_group_ids = [
    aws_security_group.private_link_serverless_other_region_original_env.id,
  ]

  subnet_ids          = [ for index in [0,1,2]: aws_subnet.public_subnets_other[index].id ]
  tags = {
      Name = "${var.resource_prefix}_private_link_serverless_other_region_original_env"
  }

  # Only for AWS and AWS Marketplace partner services. We configure our own hosted zone instead
  private_dns_enabled = false
}

# Set up a private link connection in Confluent Cloud, which connects the private endpoint to the private link attachment
resource "confluent_private_link_attachment_connection" "private_link_serverless_other_region_original_env" {
  display_name ="${local.resource_prefix}_platt"
  environment {
    id = confluent_environment.cc_env.id
  }
  aws {
    vpc_endpoint_id = aws_vpc_endpoint.private_link_serverless_other_region_original_env.id
  }
  private_link_attachment {
    id = confluent_private_link_attachment.private_link_serverless_other_region_original_env.id
  }
}

# DNS for the private link connection to the serverless products (i.e. schema registry)
resource "aws_route53_record" "private_link_serverless_vpc_two_other_region_wildcard_record" {
  zone_id = aws_route53_zone.private_link_serverless_vpc_two_other_region.zone_id
  name    = "*.${aws_route53_zone.private_link_serverless_vpc_two_other_region.name}"
  type    = "CNAME"
  ttl     = "60"
  records = [
    aws_vpc_endpoint.private_link_serverless_other_region_other_env.dns_entry[0].dns_name
  ]
  provider = aws.aws_region_other
}

# This is just a dirty hack for this demo: As setting up new regional private links to schema registry takes some time, the output 
# "schema_registry_private_endpoint_other_region" will fail if we don't wait a bit
#resource "time_sleep" "wait_for_regional_private_link_to_schema_registry" {
#  create_duration = "20s"
#  depends_on = [ 
#    confluent_kafka_cluster.cc_cluster_other_region_same_environment,
#    aws_route53_record.private_link_serverless_other_region,
#    confluent_private_link_attachment_connection.private_link_serverless_other_region
#   ]
#}
output "schema_registry_private_endpoint_other_region_main_env" {
  value = data.confluent_schema_registry_cluster.cc_env_schema_registry.private_regional_rest_endpoints[var.aws_region_other]
  # We need to delay the execution of the above statement slightly by adding dependencies, otherwise the private regional endpoint
  # for the schema registry instance for the "aws.aws_region_other" might not be available yet (as it is still provisioning)
}
