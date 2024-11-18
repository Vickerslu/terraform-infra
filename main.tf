# Azure Provider
provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "lab" {
  name     = "${var.deployment_name}-terraform-lab-rg"
  location = "UK South"
}

# Virtual Network
resource "azurerm_virtual_network" "lab_vnet" {
  name                = "${var.deployment_name}-lab-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
}

# Subnets
resource "azurerm_subnet" "jumpbox" {
  name                 = "${var.deployment_name}-jumpbox-subnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "linuxvm" {
  name                 = "${var.deployment_name}-linuxvm-subnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Network Security Groups
resource "azurerm_network_security_group" "jumpbox_nsg" {
  name                = "${var.deployment_name}-jumpbox-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "0.0.0.0/0"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "linuxvm_nsg" {
  name                = "${var.deployment_name}-linuxvm-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "0.0.0.0/0"
    destination_address_prefix = "*"
  }
}

# Azure Key Vault
resource "azurerm_key_vault" "vault" {
  name                = "${var.deployment_name}-lab-keyvault"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  access_policy {
    tenant_id = var.tenant_id
    object_id = "70cd0716-a94e-4f72-828a-b6ac00281a44"
    secret_permissions = [
      "Get",
      "List",
      "Set",
    ]
  }
}

# Generate SSH Key Pair
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Store SSH Public Key in Key Vault
resource "azurerm_key_vault_secret" "ssh_public_key" {
  name         = "${var.deployment_name}-ssh-public-key"
  value        = tls_private_key.ssh_key.public_key_openssh
  key_vault_id = azurerm_key_vault.vault.id
}

resource "azurerm_key_vault_secret" "ssh_private_key" {
  name         = "${var.deployment_name}-ssh-private-key"
  value        = tls_private_key.ssh_key.private_key_pem
  key_vault_id = azurerm_key_vault.vault.id
}

# Jump Box Public IP
resource "azurerm_public_ip" "jumpbox_ip" {
  name                = "jumpbox-public-ip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Basic"
  lifecycle {
    create_before_destroy = true
  }
}

# Jump Box NIC
resource "azurerm_network_interface" "jumpbox_nic" {
  name                = "${var.deployment_name}-jumpbox-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "${var.deployment_name}-jumpbox-ip"
    subnet_id                     = azurerm_subnet.jumpbox.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jumpbox_ip.id
  }
}

# Linux VM NIC
resource "azurerm_network_interface" "linuxvm_nic" {
  name                = "${var.deployment_name}-linuxvm-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "${var.deployment_name}-linuxvm-ip"
    subnet_id                     = azurerm_subnet.linuxvm.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Jump Box VM
resource "azurerm_linux_virtual_machine" "jumpbox" {
  name                = "${var.deployment_name}-jumpbox"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  network_interface_ids = [
    azurerm_network_interface.jumpbox_nic.id
  ]

  # Azure AD login configuration
  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.ssh_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}

# Linux VM
resource "azurerm_linux_virtual_machine" "linuxvm" {
  name                = "${var.deployment_name}-linuxvm"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  network_interface_ids = [
    azurerm_network_interface.linuxvm_nic.id
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.ssh_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  custom_data = filebase64("cloud-init.yml")
}
