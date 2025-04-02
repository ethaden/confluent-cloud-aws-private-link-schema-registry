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
