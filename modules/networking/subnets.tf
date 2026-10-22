# =========
#  Subnets
# =========

# AKS nodes. Pods use CNI Overlay, so only nodes take VNet addresses.
# Service endpoints keep Key Vault and Storage traffic on the Azure backbone.
# Postgres Flexible Server has no service endpoint support - public access with firewall rules instead.
resource "azurerm_subnet" "aks_nodes" {
  name                 = "aks-nodes-subnet"
  resource_group_name  = azurerm_resource_group.networking_rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.aks_nodes_address_prefixes

  service_endpoint {
    service = "Microsoft.KeyVault"
  }

  service_endpoint {
    service = "Microsoft.Storage"
  }
}

# Reserved for Azure Firewall (egress control, target design).
# Name is fixed by Azure. Created empty - no firewall deployed.
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.networking_rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.firewall_address_prefixes
}
