# ===============
#  Log Analytics
# ===============
# Destination for Container Insights (cluster module).

# Pinned to North Europe; PostgreSQL has its own regional exception too.
# The Container Insights DCR must be in the same region - see modules/cluster/_monitoring.tf
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "${local.name}-log-analytics"
  resource_group_name = azurerm_resource_group.shared_rg.name
  location            = "northeurope"
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}
