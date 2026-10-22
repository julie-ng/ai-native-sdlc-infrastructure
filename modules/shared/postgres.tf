# ============
#  PostgreSQL
# ============
# One server, separate databases for workflow service and Argo (ADR-005).
# Entra ID auth only - no stored password.
#
# Network: Flexible Server supports VNet integration or public access, not service endpoints.
# Public access, allowlisted to the cluster egress IP and admin IPs.
# Traffic uses the public endpoint, not the Azure backbone.

resource "azurerm_postgresql_flexible_server" "postgres" {
  name                          = "${local.name_suffixed}-psql"
  resource_group_name           = azurerm_resource_group.shared_rg.name
  location                      = azurerm_resource_group.shared_rg.location
  version                       = var.postgres_version
  sku_name                      = var.postgres_sku_name
  storage_mb                    = 32768
  backup_retention_days         = 7
  public_network_access_enabled = true
  tags                          = var.tags

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }

  lifecycle {
    ignore_changes = [
      zone # Azure picks one if unset
    ]
  }
}

# Human admin = whoever `az login` signed in as. Platform identities get database roles
# via SQL after apply - see README.
# Assumes a user sign-in; a service principal has no azuread_user.
data "azuread_user" "current" {
  object_id = data.azurerm_client_config.current.object_id
}

resource "azurerm_postgresql_flexible_server_active_directory_administrator" "admin" {
  server_name         = azurerm_postgresql_flexible_server.postgres.name
  resource_group_name = azurerm_resource_group.shared_rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = data.azurerm_client_config.current.object_id
  principal_name      = data.azuread_user.current.user_principal_name
  principal_type      = "User"
}

resource "azurerm_postgresql_flexible_server_database" "dbs" {
  for_each  = toset(var.postgres_databases)
  name      = each.value
  server_id = azurerm_postgresql_flexible_server.postgres.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  lifecycle {
    prevent_destroy = true
  }
}

# Firewall Rules
# --------------

resource "azurerm_postgresql_flexible_server_firewall_rule" "cluster_egress" {
  name             = "cluster-egress"
  server_id        = azurerm_postgresql_flexible_server.postgres.id
  start_ip_address = var.egress_ip_address
  end_ip_address   = var.egress_ip_address
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "admin" {
  for_each         = toset(var.admin_ip_ranges)
  name             = "admin-${replace(replace(each.value, ".", "-"), "/", "_")}"
  server_id        = azurerm_postgresql_flexible_server.postgres.id
  start_ip_address = cidrhost(each.value, 0)
  end_ip_address   = cidrhost(each.value, -1)
}
