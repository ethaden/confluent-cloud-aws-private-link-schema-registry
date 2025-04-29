
resource "azurerm_resource_group" "azure" {
  name     = "${var.resource_prefix}_rg"
  location = var.azure_region
}

resource "azurerm_virtual_network" "azure" {
  name                = "${var.resource_prefix}-network"
  resource_group_name = azurerm_resource_group.azure.name
  location            = azurerm_resource_group.azure.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "azure" {
  name                 = "${var.resource_prefix}-internal"
  virtual_network_name = azurerm_virtual_network.azure.name
  resource_group_name  = azurerm_resource_group.azure.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_interface" "azure" {
  name                = "${var.resource_prefix}-nic"
  resource_group_name = azurerm_resource_group.azure.name
  location            = azurerm_resource_group.azure.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.azure.id
    private_ip_address_allocation = "Dynamic"
  }
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
}

# resource "confluent_private_link_attachment" "cc_env_azure" {
#   cloud        = "AZURE"
#   region       = var.azure_region
#   display_name = "${var.resource_prefix}-platt"
#   environment {
#     id = confluent_environment.cc_env.id
#   }
# }

# resource "azurerm_private_dns_zone" "cc_env" {
#   resource_group_name = data.azurerm_resource_group.azure.name

#   name = confluent_private_link_attachment.cc_env_azure.dns_domain
# }

# resource "azurerm_private_endpoint" "cc_env_azure" {
#   name                = "${var.resource_prefix}-confluent-1"
#   location            = var.azure_region
#   resource_group_name = data.azurerm_resource_group.azure.name

#   subnet_id = azurerm_subnet.subnet[1].id

#   private_service_connection {
#     name                              = "${var.resource_prefix}-confluent-1"
#     is_manual_connection              = true
#     private_connection_resource_alias = confluent_private_link_attachment.cc_env_azure.azure[0].private_link_service_alias
#     request_message                   = "PL"
#   }
# }

# resource "confluent_private_link_attachment_connection" "cc_env_azure" {
#   display_name = "staging-azure-plattc"
#   environment {
#     id = confluent_environment.cc_env.id
#   }
#   azure {
#     private_endpoint_resource_id = azure_privatelink.vpc_endpoint_id
#   }

#   private_link_attachment {
#     id = confluent_private_link_attachment.cc_env_azure.id
#   }
# }


# resource "azurerm_private_dns_zone_virtual_network_link" "cc_env_azure" {
#   name                  = azurerm_virtual_network.azure.name
#   resource_group_name   = azurerm_resource_group.azure.name
#   private_dns_zone_name = azurerm_private_dns_zone.cc_env_azure.name
#   virtual_network_id    = azurerm_virtual_network.azure.id
# }

# resource "azurerm_private_dns_a_record" "cc_env_azure" {
#   name                = "*"
#   zone_name           = azurerm_private_dns_zone.cc_env_azure.name
#   resource_group_name = azurerm_resource_group.azure.name
#   ttl                 = 60
#   records = [
#     azurerm_private_endpoint.cc_env_azure.private_service_connection[0].private_ip_address
#   ]
# }
