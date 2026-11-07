# =====================
#  Workload Identities
# =====================
# Platform services plus the approved planner/coder secret-read exception (#26).

resource "azurerm_user_assigned_identity" "workloads" {
  for_each            = var.workload_identities
  name                = "${each.value}-mi"
  resource_group_name = azurerm_resource_group.identities_rg.name
  location            = azurerm_resource_group.identities_rg.location
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}
