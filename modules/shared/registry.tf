# ====================
#  Container Registry
# ====================
# Basic SKU: no network rules or private endpoints - public endpoint, Entra auth.
# Pull access for the kubelet is assigned in the identities module.

resource "azurerm_container_registry" "acr" {
  name                = "${local.name_squished}cr"
  resource_group_name = azurerm_resource_group.shared_rg.name
  location            = azurerm_resource_group.shared_rg.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}
