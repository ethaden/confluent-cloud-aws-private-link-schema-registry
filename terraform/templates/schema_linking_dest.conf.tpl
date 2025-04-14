# Config file for setting up schema linking to this Schema Registry instance as destination
# For setting up schema linking from ${cc_env_source_id} to ${cc_env_dest_id}, run these commands (use a user account with sufficient permissions)
# confluent login
# confluent environment use ${cc_env_source_id}
# confluent api-key create --resource ${cc_schema_registry_source_id}
# confluent schema-registry exporter create test-exporter --subjects ":*:" --config schema_linking_dest.conf
schema.registry.url=${schema_registry_url}
# Note: For kafka-avro-console-producer and kafka-avro-console-consumer, the following properties MUST be specified on the command 
# line (the tools will just ignore these settings in the config file).
basic.auth.credentials.source=USER_INFO
basic.auth.user.info=${schema_registry_user}:${schema_registry_password}
