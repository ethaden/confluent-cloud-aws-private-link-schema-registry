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
    depends_on = [ confluent_kafka_cluster.cc_cluster_other ]
}

resource "confluent_kafka_cluster" "cc_cluster_other" {
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
}

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
   Name = "Project VPC IG"
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
   Name = "2nd Route Table"
 }
}

resource "aws_key_pair" "ssh_key_other" {
  key_name   = var.ssh_key_name
  public_key = var.ssh_key_public
  provider = aws.aws_region_other
}

data "aws_ami" "ubuntu_noble" {

    most_recent = true

    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
    }

    filter {
        name = "virtualization-type"
        values = ["hvm"]
    }

    owners = ["099720109477"]
    provider = aws.aws_region_other
}

resource "aws_instance" "aws_test_vm" {
  ami = data.aws_ami.ubuntu_noble.id
  instance_type     = "t2.micro"
  key_name = aws_key_pair.ssh_key_other.key_name
  subnet_id                   = aws_subnet.public_subnets_other[0].id
  associate_public_ip_address = true
  provider = aws.aws_region_other

  root_block_device {
    delete_on_termination = true
    volume_size           = 50
    volume_type           = "gp3"
    tags                  = local.confluent_tags
    encrypted             = true
  }
  metadata_options {
    http_tokens = "required" # recommended by AWS
  }
  tags = {
    Name = "${local.resource_prefix}-vm-other-region"
  }
}

# Confluent Cloud Private Link

# Create a private link attachment in Confluent Cloud
resource "confluent_private_link_attachment" "private_link_serverless_other_region" {
  cloud = "AWS"
  region = var.aws_region_other
  display_name = "${local.resource_prefix}_private_link_serverless_other_region"
  environment {
    id = confluent_environment.cc_env.id
  }
}

resource "aws_security_group" "private_link_serverless_other_region" {
  name        = "${local.resource_prefix}_private_link_serverless_other_region"
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
resource "aws_vpc_endpoint" "private_endpoint_serverless_other" {
  vpc_id            = aws_vpc.aws_vpc_other.id
  service_name      =  confluent_private_link_attachment.private_link_serverless_other_region.aws[0].vpc_endpoint_service_name
  vpc_endpoint_type = "Interface"
  provider = aws.aws_region_other

  security_group_ids = [
    aws_security_group.private_link_serverless_other_region.id,
  ]

  subnet_ids          = [ 
    aws_subnet.public_subnets_other[0].id,
    aws_subnet.public_subnets_other[1].id,
    aws_subnet.public_subnets_other[2].id
   ]
  # Only for AWS and AWS Marketplace partner services. We configure our own hosted zone instead
  private_dns_enabled = false
}

# Set up a private link connection in Confluent Cloud, which connects the private endpoint to the private link attachment
resource "confluent_private_link_attachment_connection" "private_link_serverless_other_region" {
  display_name ="${local.resource_prefix}_platt"
  environment {
    id = confluent_environment.cc_env.id
  }
  aws {
    vpc_endpoint_id = aws_vpc_endpoint.private_endpoint_serverless_other.id
  }
  private_link_attachment {
    id = confluent_private_link_attachment.private_link_serverless_other_region.id
  }
}

# DNS for the private link connection to the serverless products (i.e. schema registry)
resource "aws_route53_zone" "private_link_serverless_other_region" {
  name = "${var.aws_region}.aws.private.confluent.cloud"
  provider = aws.aws_region_other

  vpc {
    vpc_id = aws_vpc.aws_vpc_other.id
  }
}

resource "aws_route53_record" "private_link_serverless_other_region" {
  zone_id = aws_route53_zone.private_link_serverless_other_region.zone_id
  name    = "*.${aws_route53_zone.private_link_serverless_other_region.name}"
  type    = "CNAME"
  ttl     = "60"
  records = [
    aws_vpc_endpoint.private_endpoint_serverless_other.dns_entry[0].dns_name
  ]
  provider = aws.aws_region_other
}
