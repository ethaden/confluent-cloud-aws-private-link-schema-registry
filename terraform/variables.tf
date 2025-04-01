
# Recommendation: Overwrite the default in tfvars or stick with the automatic default
variable "tf_last_updated" {
    type = string
    default = ""
    description = "Set this (e.g. in terraform.tfvars) to set the value of the tf_last_updated tag for all resources. If unset, the current date/time is used automatically."
}

variable "purpose" {
    type = string
    default = "Testing"
    description = "The purpose of this configuration, used e.g. as tags for AWS resources"
}

variable "username" {
    type = string
    default = ""
    description = "Username, used to define local.username if set here. Otherwise, the logged in username is used."
}

variable "owner" {
    type = string
    default = ""
    description = "All resources are tagged with an owner tag. If none is provided in this variable, a useful value is derived from the environment"
}

# The validator uses a regular expression for valid email addresses (but NOT complete with respect to RFC 5322)
variable "owner_email" {
    type = string
    default = ""
    description = "All resources are tagged with an owner_email tag. If none is provided in this variable, a useful value is derived from the environment"
    validation {
        condition = anytrue([
            var.owner_email=="",
            can(regex("^[a-zA-Z0-9_.+-]+@([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9]+)*\\.)+[a-zA-Z]+$", var.owner_email))
        ])
        error_message = "Please specify a valid email address for variable owner_email or leave it empty"
    }
}

variable "owner_fullname" {
    type = string
    default = ""
    description = "All resources are tagged with an owner_fullname tag. If none is provided in this variable, a useful value is derived from the environment"
}

variable "resource_prefix" {
    type = string
    default = ""
    description = "This string will be used as prefix for generated resources. Default is to use the username"
}

variable "generated_files_path" {
    description = "The main path to write generated files to"
    type = string
    default = "./generated"
}

variable "ccloud_environment_name" {
    type = string
    description = "Name of the Confluent Cloud environment to create"
}

variable "ccloud_cluster_name" {
    type = string
    description = "Name of the cluster to be created"
}

variable "aws_region" {
    type = string
    default = "eu-central-1"
    description = "The region used to deploy the AWS resources and Confluent Cloud Kafka cluster"
}

variable "aws_account_id" {
    type = string
    description = "The AWS Account ID that will be granted access to the private link access"
}

variable "vpc_id" {
    type = string
    description = "The Id of the VPC to connect the transit gateway to"
}

variable "ccloud_cluster_type" {
    type = string
    default = "dedicated"
    description = "The cluster type of the Confluent Cloud Kafka cluster. Valid values are \"basic\", \"standard\", \"dedicated\", \"enterprise\", \"freight\""
    validation {
        condition = var.ccloud_cluster_type=="basic" || var.ccloud_cluster_type=="standard" || var.ccloud_cluster_type=="dedicated" || var.ccloud_cluster_type=="enterprise" || var.ccloud_cluster_type=="freight"
        error_message = "Valid Confluent Cloud cluster types are \"basic\", \"standard\", \"dedicated\", \"enterprise\""
    }
}

variable "ccloud_cluster_availability" {
    type = string
    default = "SINGLE_ZONE"
    description = "The availability of the Confluent Cloud Kafka cluster"
    validation {
        condition = var.ccloud_cluster_availability=="SINGLE_ZONE" || var.ccloud_cluster_availability=="MULTI_ZONE"
        error_message = "The availability of the Confluent Cloud cluster must either by \"SINGLE_ZONE\" or \"MULTI_ZONE\""
    }
}

variable "ccloud_cluster_ckus" {
    type = number
    default = 1
    description = "The number of CKUs to use if the Confluent Cloud Kafka cluster is \"dedicated\"."
    validation {
        condition = var.ccloud_cluster_ckus>=1
        error_message = "The minimum number of CKUs for a dedicated cluster is 2"
    }
}

variable "ccloud_cluster_topic" {
    type = string
    default = "test"
    description = "The name of the Kafka topic to create and to subscribe to"
}

variable "ccloud_cluster_producer_write_topic_prefixes" {
    type = list
    description = "A list of Kafka topic prefixes to grant write access to the example producer"
}

variable "ccloud_cluster_consumer_read_topic_prefixes" {
    type = list
    description = "A list of Kafka topic prefixes to grant read access to the example consumer"
}

variable "ccloud_cluster_consumer_group_prefixes" {
    type = list
    description = "A list of Kafka consumer group prefixes to grant read access to the example consumer"
}

variable "ccloud_cluster_generate_client_config_files" {
    type = bool
    default = false
    description = "Set to true if you want to generate client configs with the created API keys under subfolder \"generated/client-configs\""
}
