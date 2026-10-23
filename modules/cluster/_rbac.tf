# ==================
#  Role Assignments
# ==================

# =========
# Me (self)
# =========

resource "azurerm_role_assignment" "admin" {
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  scope                = azurerm_kubernetes_cluster.aks.id
  principal_id         = data.azurerm_client_config.current.object_id # Me
}
