# ===============
#  Log Analytics
# ===============
# Destination for Container Insights (cluster module).

resource "azurerm_log_analytics_workspace" "logs" {
  name                = "${local.name}-log-analytics"
  resource_group_name = azurerm_resource_group.shared_rg.name
  location            = azurerm_resource_group.shared_rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}
