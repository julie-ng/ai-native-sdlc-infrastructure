# ==================
#  Persistent Grants
# ==================

# =============
# Control Plane
# =============
# Exported identity outputs wait for these grants before cluster creation.

# Required to assign the user-assigned kubelet identity to nodes
resource "azurerm_role_assignment" "control_plane_on_kubelet_mi" {
  role_definition_name = "Managed Identity Operator"
  scope                = azurerm_user_assigned_identity.kubelet_mi.id
  principal_id         = azurerm_user_assigned_identity.control_plane_mi.principal_id
}

# Bring-your-own subnet: join nodes to it
resource "azurerm_role_assignment" "control_plane_on_nodes_subnet" {
  role_definition_name = "Network Contributor"
  scope                = var.aks_nodes_subnet_id
  principal_id         = azurerm_user_assigned_identity.control_plane_mi.principal_id
}

# Egress IP lives in the networking resource group, outside the node resource group
resource "azurerm_role_assignment" "control_plane_on_egress_ip" {
  role_definition_name = "Network Contributor"
  scope                = var.egress_ip_id
  principal_id         = azurerm_user_assigned_identity.control_plane_mi.principal_id
}

# =======
# Kubelet
# =======

resource "azurerm_role_assignment" "kubelet_acr_pull" {
  role_definition_name = "AcrPull"
  scope                = var.container_registry_id
  principal_id         = azurerm_user_assigned_identity.kubelet_mi.principal_id
}

# ===================
# Workload Identities
# ===================
# Postgres access (workflow-service, argo) is not Azure RBAC - database roles via SQL, see README.

# Artifact service - read/write blobs in the artifacts container only
resource "azurerm_role_assignment" "artifact_service_on_blob" {
  role_definition_name = "Storage Blob Data Contributor"
  scope                = var.artifacts_container_id
  principal_id         = azurerm_user_assigned_identity.workloads["artifact-service"].principal_id
}

# Artifact service - sign user delegation SAS URLs handed to agents.
# Delegation key is requested at account level; the SAS can never exceed the
# container-scoped Data Contributor grant above.
resource "azurerm_role_assignment" "artifact_service_delegator" {
  role_definition_name = "Storage Blob Delegator"
  scope                = var.artifacts_storage_account_id
  principal_id         = azurerm_user_assigned_identity.workloads["artifact-service"].principal_id
}

# Argo artifact repository. Workflow step pods (Argo executor) are NOT granted access -
# agent pods get no cloud identity (ADR-003).

# Controller - writes and garbage-collects
resource "azurerm_role_assignment" "argo_controller_on_blob" {
  role_definition_name = "Storage Blob Data Contributor"
  scope                = var.argo_container_id
  principal_id         = azurerm_user_assigned_identity.workloads["argo-workflow-controller"].principal_id
}

# Server - reads for the UI
resource "azurerm_role_assignment" "argo_server_on_blob" {
  role_definition_name = "Storage Blob Data Reader"
  scope                = var.argo_container_id
  principal_id         = azurerm_user_assigned_identity.workloads["argo-server"].principal_id
}

# Token broker - read the GitHub App private key
resource "azurerm_role_assignment" "token_broker_on_kv" {
  role_definition_name = "Key Vault Secrets User"
  scope                = var.key_vault_id
  principal_id         = azurerm_user_assigned_identity.workloads["token-broker"].principal_id
}
