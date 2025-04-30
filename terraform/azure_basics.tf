
resource "azurerm_resource_group" "azure" {
  name     = "${var.resource_prefix}_rg"
  location = var.azure_region
  tags = local.confluent_tags
#  tags = merge(local.confluent_tags, {
#    workload = "data lake"
#  })
}

resource "azurerm_virtual_network" "azure" {
  name                = "${var.resource_prefix}-network"
  resource_group_name = azurerm_resource_group.azure.name
  location            = azurerm_resource_group.azure.location
  address_space       = ["10.0.0.0/16"]
  tags = local.confluent_tags
}

resource "azurerm_subnet" "azure" {
  name                 = "${var.resource_prefix}-internal"
  virtual_network_name = azurerm_virtual_network.azure.name
  resource_group_name  = azurerm_resource_group.azure.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "azure" {
  name                = "${var.resource_prefix}-public"
  resource_group_name = azurerm_resource_group.azure.name
  location            = azurerm_resource_group.azure.location
  allocation_method   = "Static"
  tags = local.confluent_tags
}

resource "azurerm_network_interface" "azure" {
  name                = "${var.resource_prefix}-nic"
  resource_group_name = azurerm_resource_group.azure.name
  location            = azurerm_resource_group.azure.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.azure.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.azure.id
  }
  tags = local.confluent_tags
}

resource "azurerm_network_security_group" "azure_vm" {
  name                = "${var.resource_prefix}-vm"
  location            = azurerm_resource_group.azure.location
  resource_group_name = azurerm_resource_group.azure.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  tags = local.confluent_tags
}
# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "example" {
  network_interface_id      = azurerm_network_interface.azure.id
  network_security_group_id = azurerm_network_security_group.azure_vm.id
}

# data "azurerm_image" "azure" {
#   name                = "ubuntu-24_04-lts"
#   resource_group_name = "packerimages"
# }

# Find VM with
# az vm image list --publisher "Canonical" --output table --all

resource "azurerm_linux_virtual_machine" "azure" {
  name                = "${var.resource_prefix}-vm"
  resource_group_name = azurerm_resource_group.azure.name
  location            = azurerm_resource_group.azure.location
  size                = "Standard_B2s"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.azure.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = var.ssh_key_public
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }
  tags = local.confluent_tags
}

resource "confluent_private_link_attachment" "cc_env_azure" {
  cloud        = "AZURE"
  region       = var.azure_region
  display_name = "${var.resource_prefix}-platt"
  environment {
    id = confluent_environment.cc_env.id
  }
}

resource "azurerm_private_endpoint" "cc_env_azure" {
  name                = "${var.resource_prefix}-confluent-1"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.azure.name

  subnet_id = azurerm_subnet.azure.id

  private_service_connection {
    name                              = "${var.resource_prefix}-confluent-1"
    is_manual_connection              = true
    private_connection_resource_alias = confluent_private_link_attachment.cc_env_azure.azure[0].private_link_service_alias
    request_message                   = "PL"
  }
  tags = local.confluent_tags
}

resource "confluent_private_link_attachment_connection" "cc_env_azure" {
  display_name = "${var.resource_prefix}-plattc"
  environment {
    id = confluent_environment.cc_env.id
  }
  azure {
    private_endpoint_resource_id = azurerm_private_endpoint.cc_env_azure.id
  }

  private_link_attachment {
    id = confluent_private_link_attachment.cc_env_azure.id
  }
}

# This cluster is only required for initiating the Confluent-internal connectivity to the Schema Registry
# Azure Region: configured Azure region
# Environment: original environment
# Note: This will trigger creation of a private endpoint in the Azure region
resource "confluent_kafka_cluster" "cc_cluster_azure_region_same_environment" {
  display_name = "${var.ccloud_cluster_name_other}_sr_ep_azure_region"
  availability = "SINGLE_ZONE"
  cloud        = "AZURE"
  region       = var.azure_region
  # For cost reasons, we use a basic cluster by default. However, you can choose a different type by setting the variable ccloud_cluster_type
  basic {}

  environment {
    id = confluent_environment.cc_env.id
  }

  lifecycle {
    prevent_destroy = false
  }
  # We need to add a dependency to the main cluster.
  # Otherwise, the Schema Registry instance might be spawned in var.aws_region_other if this cluster "wins the race" and is spawned first
  depends_on = [ 
    confluent_kafka_cluster.cc_cluster,
    confluent_private_link_attachment.cc_env_azure,
    confluent_private_link_attachment_connection.cc_env_azure,
    #aws_route53_record.private_link_serverless_vpc_one_original_zone_wildcard_record
  ]
}

resource "azurerm_private_dns_zone" "azure" {
  resource_group_name = azurerm_resource_group.azure.name

  name = confluent_private_link_attachment.cc_env_azure.dns_domain
}
resource "azurerm_private_dns_zone_virtual_network_link" "cc_env_azure" {
  name                  = azurerm_virtual_network.azure.name
  resource_group_name   = azurerm_resource_group.azure.name
  private_dns_zone_name = azurerm_private_dns_zone.azure.name
  virtual_network_id    = azurerm_virtual_network.azure.id
  tags = local.confluent_tags
}

# This is currently not working because no private regional rest endpoint is created cross CSP
# resource "azurerm_private_dns_a_record" "private_link_serverless_azure_schema_registry_original_env" {
#   name                = replace(data.confluent_schema_registry_cluster.cc_env_schema_registry.private_regional_rest_endpoints[var.azure_region],
#                 "https://", "")
#   zone_name           = azurerm_private_dns_zone.azure.name
#   resource_group_name = azurerm_resource_group.azure.name
#   ttl                 = 60
#   records = [
#     azurerm_private_endpoint.cc_env_azure.private_service_connection[0].private_ip_address
#   ]
#   depends_on = [
#     confluent_kafka_cluster.cc_cluster_azure_region_same_environment
#   ]
# }

resource "azurerm_private_dns_a_record" "private_link_serverless_azure_wildcard_record" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.azure.name
  resource_group_name = azurerm_resource_group.azure.name
  ttl                 = 60
  records = [
    azurerm_private_endpoint.cc_env_azure.private_service_connection[0].private_ip_address
  ]
  tags = local.confluent_tags
}

output "azure_vm_public_ip_address" {
    value = azurerm_public_ip.azure.ip_address
}
