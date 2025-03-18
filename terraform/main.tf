# TODO

locals {
  dns_domain = confluent_network.aws-private-link.dns_domain
}

data "aws_vpc" "vpc" {
    id = var.vpc_id
}

data "aws_subnets" "vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

# This will create a map from 0, 1, 2, ... to all subnets
data "aws_subnet" "vpc_subnet" {
  for_each = { for index, subnetid in data.aws_subnets.vpc_subnets.ids : index => subnetid }
  id       = each.value
}

# This will create a map from 0, 1, 2, ... to all availability zone objects
data "aws_availability_zone" "vpc_availability_zone" {
  #for_each = { for index, subnetid in data.aws_subnets.vpc_subnets.ids : index => data.aws_subnet.vpc_subnet[index].availability_zone_id }
  for_each = { for index, subnetid in data.aws_subnets.vpc_subnets.ids : index => data.aws_subnet.vpc_subnet[index].availability_zone }
  name       = each.value
}

data "aws_availability_zone" "vpc_id_to_availability_zone" {
  for_each = { for index, availability_zone in data.aws_availability_zone.vpc_availability_zone : availability_zone.name => availability_zone.name}
  name       = each.value
}

#data "aws_vpc" "privatelink" {
#  id = data.aws_vpc.vpc.id
#}

# data "aws_availability_zone" "privatelink" {
#   for_each = var.subnets_to_privatelink
#   zone_id  = each.key
# }

locals {
  bootstrap_prefix = split(".", confluent_kafka_cluster.example_aws_private_link_cluster.bootstrap_endpoint)[0]
}

resource "aws_security_group" "privatelink" {
  # Ensure that SG is unique, so that this module can be used multiple times within a single VPC
  name        = "ccloud-privatelink_${local.bootstrap_prefix}_${data.aws_vpc.vpc.id}"
  description = "Confluent Cloud Private Link minimal security group for ${confluent_kafka_cluster.example_aws_private_link_cluster.bootstrap_endpoint} in ${data.aws_vpc.vpc.id}"
  vpc_id      = data.aws_vpc.vpc.id

  ingress {
    # only necessary if redirect support from http/https is desired
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
    ipv6_cidr_blocks = [data.aws_vpc.vpc.ipv6_cidr_block]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
    ipv6_cidr_blocks = [data.aws_vpc.vpc.ipv6_cidr_block]
  }

  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
    ipv6_cidr_blocks = [data.aws_vpc.vpc.ipv6_cidr_block]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "privatelink" {
  vpc_id            = data.aws_vpc.vpc.id
  service_name      = confluent_network.aws-private-link.aws[0].private_link_endpoint_service
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.privatelink.id,
  ]

  subnet_ids          = data.aws_subnets.vpc_subnets.ids
  private_dns_enabled = false

  depends_on = [
    confluent_private_link_access.aws,
  ]
}

resource "aws_route53_zone" "privatelink" {
  name = local.dns_domain

  vpc {
    vpc_id = data.aws_vpc.vpc.id
  }
}

resource "aws_route53_record" "privatelink" {
  zone_id = aws_route53_zone.privatelink.zone_id
  name    = "*.${aws_route53_zone.privatelink.name}"
  type    = "CNAME"
  ttl     = "60"
  records = [
    aws_vpc_endpoint.privatelink.dns_entry[0]["dns_name"]
  ]
}

locals {
  endpoint_prefix = split(".", aws_vpc_endpoint.privatelink.dns_entry[0]["dns_name"])[0]
}

resource "aws_route53_record" "privatelink-zonal" {
  #for_each = var.subnets_to_privatelink
  #for_each = {
  #  "${data.terraform_remote_state.common_vpc.outputs.subnet_dualstack_1a.availability_zone_id}" = data.terraform_remote_state.common_vpc.outputs.subnet_dualstack_1a.availability_zone,
  #  "${data.terraform_remote_state.common_vpc.outputs.subnet_dualstack_1b.availability_zone_id}" = data.terraform_remote_state.common_vpc.outputs.subnet_dualstack_1b.availability_zone,
  #  "${data.terraform_remote_state.common_vpc.outputs.subnet_dualstack_1c.availability_zone_id}" = data.terraform_remote_state.common_vpc.outputs.subnet_dualstack_1c.availability_zone,
  #}
  for_each = data.aws_availability_zone.vpc_id_to_availability_zone

  zone_id = aws_route53_zone.privatelink.zone_id
  #name    = length(var.subnets_to_privatelink) == 1 ? "*" : "*.${each.key}"
  name    = "*.${each.key}"
  type    = "CNAME"
  ttl     = "60"
  records = [
    format("%s-%s%s",
      local.endpoint_prefix,
      each.value,
      replace(aws_vpc_endpoint.privatelink.dns_entry[0]["dns_name"], local.endpoint_prefix, "")
    )
  ]
}

resource "aws_s3_bucket" "bucket" {
    bucket = "${local.resource_prefix}-tech-summit-2024-private-link-s3"

  tags = {
    Name        = "${local.resource_prefix}-tech-summit-2024-private-link-s3"
  }
  lifecycle {
    prevent_destroy = false
  }
}
