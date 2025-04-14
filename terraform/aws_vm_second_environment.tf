output "cc_other_region_vm_public_dns" {
    value = aws_instance.aws_test_vm.public_dns
}


# VM in second region

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

resource "aws_security_group" "aws_test_vm" {
  name        = "${local.resource_prefix}_aws_test_vm"
  vpc_id      = aws_vpc.aws_vpc_other.id
  provider = aws.aws_region_other

  dynamic "ingress" {
    for_each = { 1 : 22 }
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

resource "aws_instance" "aws_test_vm" {
  ami = data.aws_ami.ubuntu_noble.id
  instance_type     = "t2.micro"
  key_name = aws_key_pair.ssh_key_other.key_name
  subnet_id                   = aws_subnet.public_subnets_other[0].id
  associate_public_ip_address = true
  provider = aws.aws_region_other
  vpc_security_group_ids = [
    aws_security_group.aws_test_vm.id
  ]
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
