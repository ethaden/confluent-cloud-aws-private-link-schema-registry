# These resources are required for configuring schema linking with the "confluent" CLI

# Service account for the destination cluster for Schema Linking
resource "confluent_service_account" "cc_env_schema_linking" {
  display_name = "${local.resource_prefix}_cc_env_schema_linking"
  description  = "Service Account for Schema Linking"
}

# API key for destination Schema Registry instance
resource "confluent_api_key" "cc_env_schema_registry_destination_schema_linking_api_key" {
  display_name = "${var.resource_prefix}_cc_env_schema_registry_destination_schema_linking_api_key"
  description  = "Schema Registry API Key for the destination environment, owned by '${var.resource_prefix}_cc_env_schema_linking' service account"
  owner {
    id          = confluent_service_account.cc_env_schema_linking.id
    api_version = confluent_service_account.cc_env_schema_linking.api_version
    kind        = confluent_service_account.cc_env_schema_linking.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.cc_env_schema_registry_other.id
    api_version = data.confluent_schema_registry_cluster.cc_env_schema_registry_other.api_version
    kind        = data.confluent_schema_registry_cluster.cc_env_schema_registry_other.kind

    environment {
      id = confluent_environment.cc_env_other.id
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_role_binding" "cc_env_schema_registry_destination_schema_linking_role_binding" {
  principal   = "User:${confluent_service_account.cc_env_schema_linking.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${data.confluent_schema_registry_cluster.cc_env_schema_registry_other.resource_name}/subject=*"
}

# Create config file for setting up schema linking with the "confluent" CLI
resource "local_sensitive_file" "schema_linking_dest_config_file" {
  content = templatefile("${path.module}/templates/schema_linking_dest.conf.tpl",
  {
    schema_registry_url = data.confluent_schema_registry_cluster.cc_env_schema_registry_other.private_regional_rest_endpoints[var.aws_region]
    schema_registry_user = confluent_api_key.cc_env_schema_registry_destination_schema_linking_api_key.id
    schema_registry_password = confluent_api_key.cc_env_schema_registry_destination_schema_linking_api_key.secret
    cc_env_source_id = confluent_environment.cc_env.id
    cc_env_dest_id = confluent_environment.cc_env_other.id
    cc_schema_registry_source_id = data.confluent_schema_registry_cluster.cc_env_schema_registry.id
  }
  )
  filename = "${var.generated_files_path}/schema_linking_dest.conf"
}
