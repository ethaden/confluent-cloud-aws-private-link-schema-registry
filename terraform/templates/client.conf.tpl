# Produce with this command:
# kafka-console-producer --producer.config client-${client_name}.conf --bootstrap-server ${cluster_bootstrap_server} --topic <topic>
# Produce with schema which you have specified in the environment variable $SCHEMA
# kafka-avro-console-producer --producer.config client-${client_name}.conf --bootstrap-server '${cluster_bootstrap_server}' --property schema.registry.url='${schema_registry_url}' --property basic.auth.credentials.source=USER_INFO --property basic.auth.user.info='${schema_registry_user}:${schema_registry_password}' --property value.schema='$SCHEMA' --topic <topic>
# Consume with this command:
# kafka-console-consumer --consumer.config client-${client_name}.conf --bootstrap-server ${cluster_bootstrap_server} --from-beginning --topic <topic>
# Consume with this command if using schema registry:
# kafka-avro-console-consumer --consumer.config client-${client_name}.conf --bootstrap-server '${cluster_bootstrap_server}' --property schema.registry.url='${schema_registry_url}' --property basic.auth.credentials.source=USER_INFO --property basic.auth.user.info='${schema_registry_user}:${schema_registry_password}' --from-beginning --topic <topic>

bootstrap.servers=${cluster_bootstrap_server}
security.protocol=SASL_SSL
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='${api_key}' password='${api_secret}';
sasl.mechanism=PLAIN
# Required for consumers only:
group.id=${consumer_group_prefix}${client_name}

# Schema Registry
schema.registry.url=${schema_registry_url}
# Note: For kafka-avro-console-producer and kafka-avro-console-consumer, the following properties MUST be specified on the command 
# line (the tools will just ignore these settings in the config file).
basic.auth.credentials.source=USER_INFO
basic.auth.user.info=${schema_registry_user}:${schema_registry_password}
