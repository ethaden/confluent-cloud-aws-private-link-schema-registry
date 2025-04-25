
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
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.azure.id,
  ]

  admin_ssh_key {
    username   = "${var.resource_prefix}-adminuser"
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
