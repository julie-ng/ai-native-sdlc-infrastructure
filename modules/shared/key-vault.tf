# ===========
#  Key Vault
# ===========
# Holds the GitHub App private key for the token broker (ADR-012).
# Secrets are added outside Terraform so they never land in state.

resource "azurerm_key_vault" "kv" {
  name                       = "${local.name_suffixed}-kv"
  resource_group_name        = azurerm_resource_group.shared_rg.name
  location                   = azurerm_resource_group.shared_rg.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7     # minimum
  purge_protection_enabled   = false # so we can fully delete it
  tags                       = var.tags

  # Public endpoint, reachable only from the AKS subnet (service endpoint) and admin IPs
  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [var.aks_nodes_subnet_id]
    ip_rules                   = var.admin_ip_ranges
  }
}

# Admin can manage secrets (data plane). Still needs an allowed IP to reach the vault.
resource "azurerm_role_assignment" "kv_admin" {
  role_definition_name = "Key Vault Administrator"
  scope                = azurerm_key_vault.kv.id
  principal_id         = data.azurerm_client_config.current.object_id # Me
}
