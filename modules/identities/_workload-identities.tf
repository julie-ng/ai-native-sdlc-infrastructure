# =====================
#  Workload Identities
# =====================
# Platform services only; agent ServiceAccounts get no cloud identity (ADR-003).

resource "azurerm_user_assigned_identity" "workloads" {
  for_each            = var.workload_identities
  name                = "${each.value}-mi"
  resource_group_name = azurerm_resource_group.identities_rg.name
  location            = azurerm_resource_group.identities_rg.location
  tags                = var.tags

  # Temporarily allow replacement of the unused identities in #19.
  # Restore prevent_destroy after the human applies the identity changes.
}
