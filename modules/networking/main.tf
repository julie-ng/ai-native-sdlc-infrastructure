# ================
#  Resource Group
# ================
# Longer lifecycle than the cluster - no suffix.

resource "azurerm_resource_group" "networking_rg" {
  name     = "${local.name}-networking-rg"
  location = var.location
  tags     = var.tags
}

locals {
  name = lower(var.name)
}

# =================
#  Virtual Network
# =================

resource "azurerm_virtual_network" "vnet" {
  name                = "${local.name}-vnet"
  location            = azurerm_resource_group.networking_rg.location
  resource_group_name = azurerm_resource_group.networking_rg.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}
