# This file contains just the very basic AWS setup

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
data "aws_availability_zone" "vpc_subnet_to_availability_zone" {
  #for_each = { for index, subnetid in data.aws_subnets.vpc_subnets.ids : index => data.aws_subnet.vpc_subnet[index].availability_zone_id }
  for_each = { for index, subnetid in data.aws_subnets.vpc_subnets.ids : index => data.aws_subnet.vpc_subnet[index].availability_zone }
  name       = each.value
}

data "aws_availability_zone" "vpc_availability_zone_name_to_zone" {
  for_each = { for index, availability_zone in data.aws_availability_zone.vpc_subnet_to_availability_zone : availability_zone.name => availability_zone.name}
  name       = each.value
}

# resource "aws_s3_bucket" "bucket" {
#     bucket = "${local.resource_prefix}--s3"

#   tags = {
#     Name        = "${local.resource_prefix}-s3"
#   }
#   lifecycle {
#     prevent_destroy = false
#   }
# }


# Set up second region
# AWS
resource "aws_vpc" "aws_vpc_other" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames = true
  enable_dns_support   = true
  provider = aws.aws_region_other
  tags = {
    Name = "${var.resource_prefix}_vpc"
  }
}

resource "aws_subnet" "public_subnets_other" {
  count             = length(var.public_subnet_cidrs_other)
  vpc_id            = aws_vpc.aws_vpc_other.id
  cidr_block        = element(var.public_subnet_cidrs_other, count.index)
  availability_zone = element(var.azs_other, count.index)
  enable_resource_name_dns_a_record_on_launch = true
  map_public_ip_on_launch = true
  provider = aws.aws_region_other
 
  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

resource "aws_internet_gateway" "gw_other" {
 vpc_id = aws_vpc.aws_vpc_other.id
 provider = aws.aws_region_other
 
 tags = {
   Name = "${var.resource_prefix}_igw"
 }
}

resource "aws_route_table" "second_rt_other" {
 vpc_id = aws_vpc.aws_vpc_other.id
 provider = aws.aws_region_other
 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.gw_other.id
 }

 tags = {
   Name = "${var.resource_prefix}_2nd_Route_Table"
 }
}

resource "aws_route_table_association" "second_rt_other" {
    #for_each = {for subnet in aws_subnet.public_subnets_other:  subnet.id => subnet}
    #for_each = toset(aws_subnet.public_subnets_other[*].id)
    for_each = {for id in [0,1,2]: id => aws_subnet.public_subnets_other[id]}
    subnet_id      = each.value.id
    route_table_id = aws_route_table.second_rt_other.id
    provider = aws.aws_region_other
}


# DNS

# Every VPC has exactly one (!) hosted zone per AWS region

resource "aws_route53_zone" "privatelink_serverless_other_region_other_env" {
  name = "${var.aws_region_other}.aws.private.confluent.cloud"

  vpc {
    vpc_id = aws_vpc.aws_vpc_other.id
  }
}
