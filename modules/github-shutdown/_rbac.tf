# =======================
#  Resource-scoped Grants
# =======================
# Built-in roles also permit changes/deletion; scope each to its exact resource.

resource "azurerm_role_assignment" "aks" {
  scope                = var.aks_cluster_id
  role_definition_name = var.settings.aks_role
  principal_id         = azurerm_user_assigned_identity.shutdown.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "postgres" {
  scope                = var.postgres_server_id
  role_definition_name = var.settings.postgres_role
  principal_id         = azurerm_user_assigned_identity.shutdown.principal_id
  principal_type       = "ServicePrincipal"
}
