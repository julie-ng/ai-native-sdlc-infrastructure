# ==============
#  Blob Storage
# ==============
# Backs the artifact service (ADR-005). Agents never touch it directly.

resource "azurerm_storage_account" "storage" {
  name                     = "${local.name_squished}storage"
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
resource "azurerm_storage_container" "artifacts" {
  name                  = "artifacts"
  storage_account_id    = azurerm_storage_account.storage.id
  container_access_type = "private"
}
