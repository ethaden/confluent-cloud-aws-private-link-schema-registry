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
