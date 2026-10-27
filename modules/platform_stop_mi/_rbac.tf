# =======================
#  Resource-scoped Grants
# =======================
# Built-in roles also permit changes/deletion; scope each to its exact resource.

resource "azurerm_role_assignment" "aks_contributor" {
  scope                = var.aks_cluster_id
  role_definition_name = var.settings.aks_role
  principal_id         = azurerm_user_assigned_identity.stop.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "postgres_contributor" {
  scope                = var.postgres_server_id
  role_definition_name = var.settings.postgres_role
  principal_id         = azurerm_user_assigned_identity.stop.principal_id
  principal_type       = "ServicePrincipal"
}
