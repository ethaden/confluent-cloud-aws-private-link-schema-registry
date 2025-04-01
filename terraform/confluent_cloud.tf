# Confluent Cloud Environment

resource "confluent_environment" "example_env" {
  display_name = var.ccloud_environment_name

  stream_governance {
    package = "ESSENTIALS"
  }

  lifecycle {
    prevent_destroy = false
  }
}

data "confluent_schema_registry_cluster" "example_schema_registry" {
    environment {
      id = confluent_environment.example_env.id
    }
    # Using this dependency avoids a potential race condition where the schema registry is still created while terraform already tries to access it (which will fail)
    depends_on = [ confluent_kafka_cluster.example_aws_private_link_cluster ]
}

resource "confluent_service_account" "example_env_admin" {
  display_name = "${var.resource_prefix}_example_sa_env_admin"
  description  = "Service Account Example Environment Admin (just for accessing Schema Registry)"
}

resource "confluent_api_key" "example_schema_registry_admin_api_key" {
  display_name = "${var.resource_prefix}_schema_registry_admin_api_key"
  description  = "Schema Registry API Key that is owned by '${var.resource_prefix}_example_sa_env_admin' service account"
  owner {
    id          = confluent_service_account.example_env_admin.id
    api_version = confluent_service_account.example_env_admin.api_version
    kind        = confluent_service_account.example_env_admin.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.example_schema_registry.id
    api_version = data.confluent_schema_registry_cluster.example_schema_registry.api_version
    kind        = data.confluent_schema_registry_cluster.example_schema_registry.kind

    environment {
      id = confluent_environment.example_env.id
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_role_binding" "example_schema_registry_admin_role_binding" {
  principal   = "User:${confluent_service_account.example_env_admin.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${data.confluent_schema_registry_cluster.example_schema_registry.resource_name}/subject=*"
}

data "confluent_schema_registry_cluster_config" "example_schema_registry" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.example_schema_registry.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.example_schema_registry.rest_endpoint
  credentials {
    key    = confluent_api_key.example_schema_registry_admin_api_key.id
    secret = confluent_api_key.example_schema_registry_admin_api_key.secret
  }
  depends_on = [ confluent_role_binding.example_schema_registry_admin_role_binding ]
}



# Confluent Cloud Kafka Cluster

# Set up a basic cluster (or a standard cluster, see below)
resource "confluent_kafka_cluster" "example_aws_private_link_cluster" {
  display_name = var.ccloud_cluster_name
  availability = var.ccloud_cluster_availability
  cloud        = "AWS"
  region       = var.aws_region
  # Use standard if you want to have the ability to grant role bindings on topic scope
  # standard {}
  # For cost reasons, we use a basic cluster by default. However, you can choose a different type by setting the variable ccloud_cluster_type
  # As each different type is represented by a unique block in the cluster resource, we use dynamic blocks here.
  # Only exactly one can be active due to the way we've chosen the condition for "for_each"

  dynamic "enterprise" {
    for_each = var.ccloud_cluster_type=="enterprise" ? [true] : []
    content {
    }
  }
  dynamic "dedicated" {
    for_each = var.ccloud_cluster_type=="dedicated" ? [true] : []
    content {
        cku = var.ccloud_cluster_ckus
        
    }
  }

  network {
    id = confluent_network.aws-private-link.id
  }
  environment {
    id = confluent_environment.example_env.id
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_network" "aws-private-link" {
  display_name     = "${local.resource_prefix}_aws_private_link_network"
  cloud            = "AWS"
  region           = var.aws_region
  connection_types = ["PRIVATELINK"]
  #zones            = [
  #  data.terraform_remote_state.common_vpc.outputs.subnet_dualstack_1a.availability_zone_id,
  #  data.terraform_remote_state.common_vpc.outputs.subnet_dualstack_1b.availability_zone_id,
  #  data.terraform_remote_state.common_vpc.outputs.subnet_dualstack_1c.availability_zone_id,
  #  
  #]
  #zones = [for index, zone in data.aws_availability_zone.vpc_availability_zone : zone.id]
  environment {
    id = confluent_environment.example_env.id
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_private_link_access" "aws" {
  display_name = "${local.resource_prefix}_aws_private_link_access"
  aws {
    account = var.aws_account_id
  }
  environment {
    id = confluent_environment.example_env.id
  }
  network {
    id = confluent_network.aws-private-link.id
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Create a private link attachment in Confluent Cloud
resource "confluent_private_link_attachment" "private_link_attachment" {
  cloud = "AWS"
  region = var.aws_region
  display_name = "${local.resource_prefix}_aws_private_link_attachment"
  environment {
    id = confluent_environment.example_env.id
  }
}

resource "aws_security_group" "private_link_endpoint_sg" {
  name        = "${local.resource_prefix}_aws_private_link_endpoint_sg"
  vpc_id      = data.aws_vpc.vpc.id

#   ingress {
#     # TLS (change to whatever ports you need)
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     # Please restrict your ingress to only necessary IPs and ports.
#     # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
#     cidr_blocks = # add a CIDR block here
#   }

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
resource "aws_vpc_endpoint" "private_endpoint" {
  vpc_id            = var.vpc_id
  service_name      =  confluent_private_link_attachment.private_link_attachment.aws[0].vpc_endpoint_service_name
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.private_link_endpoint_sg.id,
  ]

  subnet_ids          = data.aws_subnets.vpc_subnets.ids
  # Only for AWS and AWS Marketplace partner services. We configure our own hosted zone instead
  private_dns_enabled = false
}

# Set up a private link connection in Confluent Cloud, which connects the private endpoint to the private link attachment
resource "confluent_private_link_attachment_connection" "aws" {
  display_name ="${local.resource_prefix}_platt"
  environment {
    id = confluent_environment.example_env.id
  }
  aws {
    vpc_endpoint_id = aws_vpc_endpoint.private_endpoint.id
  }
  private_link_attachment {
    id = confluent_private_link_attachment.private_link_attachment.id
  }
}

#output "private_link_attachment_connection" {
#  value = confluent_private_link_attachment_connection
#}

# Topic with configured name
resource "confluent_kafka_topic" "example_aws_private_link_topic_test" {
  kafka_cluster {
    id = confluent_kafka_cluster.example_aws_private_link_cluster.id
  }
  topic_name         = var.ccloud_cluster_topic
  rest_endpoint      = confluent_kafka_cluster.example_aws_private_link_cluster.rest_endpoint
  partitions_count = 1
  credentials {
    key    = confluent_api_key.example_aws_private_link_api_key_sa_cluster_admin.id
    secret = confluent_api_key.example_aws_private_link_api_key_sa_cluster_admin.secret
  }
  lifecycle {
    prevent_destroy = false
  }
}

# Service Account, API Key and role bindings for the cluster admin
resource "confluent_service_account" "example_aws_private_link_sa_cluster_admin" {
  display_name = "${local.resource_prefix}_example_aws_private_link_sa_cluster_admin"
  description  = "Service Account mTLS Example Cluster Admin"
}

# An API key with Cluster Admin access. Required for provisioning the cluster-specific resources such as our topic
resource "confluent_api_key" "example_aws_private_link_api_key_sa_cluster_admin" {
  display_name = "${local.resource_prefix}_example_aws_private_link_api_key_sa_cluster_admin"
  description  = "Kafka API Key that is owned by '${local.resource_prefix}_example_aws_private_link_sa_cluster_admin' service account"
  owner {
    id          = confluent_service_account.example_aws_private_link_sa_cluster_admin.id
    api_version = confluent_service_account.example_aws_private_link_sa_cluster_admin.api_version
    kind        = confluent_service_account.example_aws_private_link_sa_cluster_admin.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.example_aws_private_link_cluster.id
    api_version = confluent_kafka_cluster.example_aws_private_link_cluster.api_version
    kind        = confluent_kafka_cluster.example_aws_private_link_cluster.kind

    environment {
      id = confluent_environment.example_env.id
    }
  }

  lifecycle {
    prevent_destroy = false
  }
  # We could run this immediately, but we wait for DNS for the private link and the admin role binding to be configured first.
  # By waiting here, the setup of all resources using this api key will be delayed until the private link is available
  depends_on = [ 
    aws_route53_record.privatelink-zonal, 
    confluent_role_binding.example_aws_private_link_role_binding_cluster_admin
    ]
}

# Assign the CloudClusterAdmin role to the cluster admin service account
resource "confluent_role_binding" "example_aws_private_link_role_binding_cluster_admin" {
  principal   = "User:${confluent_service_account.example_aws_private_link_sa_cluster_admin.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.example_aws_private_link_cluster.rbac_crn
  lifecycle {
    prevent_destroy = false
  }
}

# Schema Registry API Key for the cluster admin (with full access to the environment's schema registry)
resource "confluent_api_key" "example_schema_registry_cluster_admin_api_key" {
  display_name = "${var.resource_prefix}_example_api_key_sa_cluster_admin_api_key"
  description  = "Schema Registry API Key that is owned by '${var.resource_prefix}_example_api_key_sa_cluster_admin' service account"
  owner {
    id          = confluent_service_account.example_aws_private_link_sa_cluster_admin.id
    api_version = confluent_service_account.example_aws_private_link_sa_cluster_admin.api_version
    kind        = confluent_service_account.example_aws_private_link_sa_cluster_admin.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.example_schema_registry.id
    api_version = data.confluent_schema_registry_cluster.example_schema_registry.api_version
    kind        = data.confluent_schema_registry_cluster.example_schema_registry.kind

    environment {
      id = confluent_environment.example_env.id
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_role_binding" "example_schema_registry_cluster_admin_role_binding" {
  principal   = "User:${confluent_service_account.example_aws_private_link_sa_cluster_admin.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${data.confluent_schema_registry_cluster.example_schema_registry.resource_name}/subject=*"
}


# Service Account, API Key and role bindings for the producer
resource "confluent_service_account" "example_aws_private_link_sa_producer" {
  display_name = "${local.resource_prefix}_example_aws_private_link_sa_producer"
  description  = "Service Account mTLS Example Producer"
}

resource "confluent_api_key" "example_aws_private_link_api_key_producer" {
  display_name = "${local.resource_prefix}_example_aws_private_link_api_key_producer"
  description  = "Kafka API Key that is owned by '${local.resource_prefix}_example_aws_private_link_sa' service account"
  owner {
    id          = confluent_service_account.example_aws_private_link_sa_producer.id
    api_version = confluent_service_account.example_aws_private_link_sa_producer.api_version
    kind        = confluent_service_account.example_aws_private_link_sa_producer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.example_aws_private_link_cluster.id
    api_version = confluent_kafka_cluster.example_aws_private_link_cluster.api_version
    kind        = confluent_kafka_cluster.example_aws_private_link_cluster.kind

    environment {
      id = confluent_environment.example_env.id
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# For role bindings such as DeveloperRead and DeveloperWrite at least a standard cluster type would be required. We use ACLs instead for basic clusters
resource "confluent_role_binding" "example_aws_private_link_role_binding_producer" {
  # Instaniciate this block only if the cluster type is NOT basic
  count = var.ccloud_cluster_type=="basic" ? 0 : 1
  principal   = "User:${confluent_service_account.example_aws_private_link_sa_producer.id}"
  role_name   = "DeveloperWrite"
  crn_pattern = "${confluent_kafka_cluster.example_aws_private_link_cluster.rbac_crn}/kafka=${confluent_kafka_cluster.example_aws_private_link_cluster.id}/topic=${confluent_kafka_topic.example_aws_private_link_topic_test.topic_name}"
  lifecycle {
    prevent_destroy = false
  }
}

# Schema Registry API Key for the example producer (with prefixed read access to the environment's schema registry)
resource "confluent_api_key" "example_schema_registry_producer_api_key" {
  display_name = "${var.resource_prefix}_example_aws_private_link_sa_producer_sr_api_key"
  description  = "Schema Registry API Key that is owned by '${var.resource_prefix}_example_aws_private_link_sa_producer_sr_api_key' service account"
  owner {
    id          = confluent_service_account.example_aws_private_link_sa_producer.id
    api_version = confluent_service_account.example_aws_private_link_sa_producer.api_version
    kind        = confluent_service_account.example_aws_private_link_sa_producer.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.example_schema_registry.id
    api_version = data.confluent_schema_registry_cluster.example_schema_registry.api_version
    kind        = data.confluent_schema_registry_cluster.example_schema_registry.kind

    environment {
      id = confluent_environment.example_env.id
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# In this demo setup, we provide write access to schema registry to the producer. Note: This is not recommended for production environments. Please manage schemas via CI/CD explicitly there.
resource "confluent_role_binding" "example_schema_registry_producer_role_binding" {
  for_each = toset(var.ccloud_cluster_producer_write_topic_prefixes)
  principal   = "User:${confluent_service_account.example_aws_private_link_sa_producer.id}"
  role_name   = "DeveloperWrite"
  crn_pattern = "${data.confluent_schema_registry_cluster.example_schema_registry.resource_name}/subject=${each.key}*"
}


# Service Account, API Key and role bindings for the consumer
resource "confluent_service_account" "example_aws_private_link_sa_consumer" {
  display_name = "${local.resource_prefix}_example_aws_private_link_sa_consumer"
  description  = "Service Account mTLS Lambda Example Consumer"
}


resource "confluent_api_key" "example_aws_private_link_api_key_consumer" {
  display_name = "${local.resource_prefix}_example_aws_private_link_api_key_consumer"
  description  = "Kafka API Key that is owned by '${local.resource_prefix}_example_aws_private_link_sa' service account"
  owner {
    id          = confluent_service_account.example_aws_private_link_sa_consumer.id
    api_version = confluent_service_account.example_aws_private_link_sa_consumer.api_version
    kind        = confluent_service_account.example_aws_private_link_sa_consumer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.example_aws_private_link_cluster.id
    api_version = confluent_kafka_cluster.example_aws_private_link_cluster.api_version
    kind        = confluent_kafka_cluster.example_aws_private_link_cluster.kind

    environment {
      id = confluent_environment.example_env.id
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# For role bindings such as DeveloperRead and DeveloperWrite at least a standard cluster type would be required. Let's use ACLs instead
resource "confluent_role_binding" "example_aws_private_link_role_binding_consumer" {
  # Instaniciate this block only if the cluster type is NOT basic
  for_each = toset(var.ccloud_cluster_consumer_read_topic_prefixes)
  principal   = "User:${confluent_service_account.example_aws_private_link_sa_consumer.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${confluent_kafka_cluster.example_aws_private_link_cluster.rbac_crn}/kafka=${confluent_kafka_cluster.example_aws_private_link_cluster.id}/topic=${each.value}"
  lifecycle {
    prevent_destroy = false
  }
}
resource "confluent_role_binding" "example_aws_private_link_role_binding_consumer_group" {
  for_each = toset(var.ccloud_cluster_consumer_read_topic_prefixes)
  principal   = "User:${confluent_service_account.example_aws_private_link_sa_consumer.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${confluent_kafka_cluster.example_aws_private_link_cluster.rbac_crn}/kafka=${confluent_kafka_cluster.example_aws_private_link_cluster.id}/group=${each.value}*"
  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_api_key" "example_schema_registry_consumer_api_key" {
  display_name = "${var.resource_prefix}_example_api_key_sa_consumer_sr_api_key"
  description  = "Schema Registry API Key that is owned by '${var.resource_prefix}_example_api_key_sa_cluster_admin' service account"
  owner {
    id          = confluent_service_account.example_aws_private_link_sa_consumer.id
    api_version = confluent_service_account.example_aws_private_link_sa_consumer.api_version
    kind        = confluent_service_account.example_aws_private_link_sa_consumer.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.example_schema_registry.id
    api_version = data.confluent_schema_registry_cluster.example_schema_registry.api_version
    kind        = data.confluent_schema_registry_cluster.example_schema_registry.kind

    environment {
      id = confluent_environment.example_env.id
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_role_binding" "example_schema_registry_consumer_role_binding" {
  for_each = toset(var.ccloud_cluster_consumer_read_topic_prefixes)
  principal   = "User:${confluent_service_account.example_aws_private_link_sa_consumer.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${data.confluent_schema_registry_cluster.example_schema_registry.resource_name}/subject=${each.key}*"
}

output "cluster_bootstrap_server" {
   value = confluent_kafka_cluster.example_aws_private_link_cluster.bootstrap_endpoint
}
output "cluster_rest_endpoint" {
    value = confluent_kafka_cluster.example_aws_private_link_cluster.rest_endpoint
}

# The next entries demonstrate how to output the generated API keys to the console even though they are considered to be sensitive data by Terraform
# Uncomment these lines if you want to generate that output
# output "cluster_api_key_admin" {
#     value = nonsensitive("Key: ${confluent_api_key.example_aws_private_link_api_key_sa_cluster_admin.id}\nSecret: ${confluent_api_key.example_aws_private_link_api_key_sa_cluster_admin.secret}")
# }

# output "cluster_api_key_producer" {
#     value = nonsensitive("Key: ${confluent_api_key.example_aws_private_link_api_key_producer.id}\nSecret: ${confluent_api_key.example_aws_private_link_api_key_producer.secret}")
# }

# output "cluster_api_key_consumer" {
#     value = nonsensitive("Key: ${confluent_api_key.example_aws_private_link_api_key_consumer.id}\nSecret: ${confluent_api_key.example_aws_private_link_api_key_consumer.secret}")
# }

# Generate console client configuration files for testing in subfolder "generated/client-configs"
# PLEASE NOTE THAT THESE FILES CONTAIN SENSITIVE CREDENTIALS
resource "local_sensitive_file" "client_config_files" {
  # Do not generate any files if var.ccloud_cluster_generate_client_config_files is false
  for_each = var.ccloud_cluster_generate_client_config_files ? {
    "admin" = { "cluster_api_key" = confluent_api_key.example_aws_private_link_api_key_sa_cluster_admin, "sr_api_key" = confluent_api_key.example_schema_registry_cluster_admin_api_key},
    "producer" = { "cluster_api_key" = confluent_api_key.example_aws_private_link_api_key_producer, "sr_api_key" = confluent_api_key.example_schema_registry_producer_api_key},
    "consumer" = { "cluster_api_key" = confluent_api_key.example_aws_private_link_api_key_consumer, "sr_api_key" = confluent_api_key.example_schema_registry_consumer_api_key}} : {}

  content = templatefile("${path.module}/templates/client.conf.tpl",
  {
    client_name = "${each.key}"
    cluster_bootstrap_server = trimprefix("${confluent_kafka_cluster.example_aws_private_link_cluster.bootstrap_endpoint}", "SASL_SSL://")
    api_key = "${each.value["cluster_api_key"].id}"
    api_secret = "${each.value["cluster_api_key"].secret}"
    consumer_group_prefix = "${var.ccloud_cluster_consumer_group_prefixes[0]}.demo"
    schema_registry_url = data.confluent_schema_registry_cluster.example_schema_registry.private_regional_rest_endpoints[var.aws_region]
    schema_registry_user = "${each.value["sr_api_key"].id}"
    schema_registry_password = "${each.value["sr_api_key"].secret}"
  }
  )
  filename = "${var.generated_files_path}/client-${each.key}.conf"
}
