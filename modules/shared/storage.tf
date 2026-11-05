# ==============
#  Blob Storage
# ==============
# Two accounts, same settings, separate access:
#   artifacts - backs the artifact service (ADR-005). Agents never touch it directly.
#   argo      - Argo Workflows artifact repository

locals {
  storage_accounts = {
    artifacts = {
      name      = "${local.name_squished}artifacts"
      container = "artifacts"
    }
    argo = {
      name      = "${local.name_squished}argo"
      container = "argo"
    }
  }
}

resource "azurerm_storage_account" "storage" {
  for_each                 = local.storage_accounts
  name                     = each.value.name
  resource_group_name      = azurerm_resource_group.shared_rg.name
  location                 = azurerm_resource_group.shared_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags

  # Entra ID only
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false

  # Public endpoint, reachable only from the AKS subnet (service endpoint) and admin IPs
  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [var.aks_nodes_subnet_id]
    ip_rules                   = local.storage_ip_rules
  }
}

# Created via the management plane (storage_account_id), so the network rules above don't block Terraform.
resource "azurerm_storage_container" "containers" {
  for_each              = local.storage_accounts
  name                  = each.value.container
  storage_account_id    = azurerm_storage_account.storage[each.key].id
  container_access_type = "private"
}

# Admin can browse and manage blobs in the portal (data plane). Account scope, not container: the
# assignee is the deployer, and account scope lets the portal list containers. Still needs an
# allowed IP in the network rules to reach the data plane.
resource "azurerm_role_assignment" "storage_admin" {
  for_each             = local.storage_accounts
  role_definition_name = "Storage Blob Data Owner"
  scope                = azurerm_storage_account.storage[each.key].id
  principal_id         = data.azurerm_client_config.current.object_id # Me
}

# ======================
#  Local Development SP
# ======================
# For running the artifact service on a laptop against real storage. No client secret or
# certificate here: credentials would land in state. Create one manually (see README).
# Only the container is writable; the delegator role at account scope is what lets the
# service sign user delegation SAS URLs, and it grants no blob access by itself.

resource "azuread_application" "local_dev" {
  display_name = "${var.name}-local-dev"
  owners       = [data.azurerm_client_config.current.object_id]
}

resource "azuread_service_principal" "local_dev" {
  client_id = azuread_application.local_dev.client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

# Not part of local.storage_accounts: only the artifacts account gets this container.
resource "azurerm_storage_container" "local_dev" {
  name                  = "local-dev"
  storage_account_id    = azurerm_storage_account.storage["artifacts"].id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "local_dev_blob_contributor" {
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_container.local_dev.id
  principal_id         = azuread_service_principal.local_dev.object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "local_dev_blob_delegator" {
  role_definition_name = "Storage Blob Delegator"
  scope                = azurerm_storage_account.storage["artifacts"].id
  principal_id         = azuread_service_principal.local_dev.object_id
  principal_type       = "ServicePrincipal"
}
