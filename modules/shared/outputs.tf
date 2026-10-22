output "resource_group" {
  value = {
    name = azurerm_resource_group.shared_rg.name
    id   = azurerm_resource_group.shared_rg.id
  }
}

output "postgres" {
  value = {
    name      = azurerm_postgresql_flexible_server.postgres.name
    id        = azurerm_postgresql_flexible_server.postgres.id
    fqdn      = azurerm_postgresql_flexible_server.postgres.fqdn
    databases = [for db in azurerm_postgresql_flexible_server_database.dbs : db.name]
  }
}

output "storage" {
  value = {
    for k, sa in azurerm_storage_account.storage : k => {
      name                  = sa.name
      id                    = sa.id
      primary_blob_endpoint = sa.primary_blob_endpoint
      container_name        = azurerm_storage_container.containers[k].name
      container_id          = azurerm_storage_container.containers[k].id
    }
  }
}

output "key_vault" {
  value = {
    name      = azurerm_key_vault.kv.name
    id        = azurerm_key_vault.kv.id
    vault_uri = azurerm_key_vault.kv.vault_uri
  }
}

output "container_registry" {
  value = {
    name         = azurerm_container_registry.acr.name
    id           = azurerm_container_registry.acr.id
    login_server = azurerm_container_registry.acr.login_server
  }
}

output "log_analytics" {
  value = {
    name = azurerm_log_analytics_workspace.logs.name
    id   = azurerm_log_analytics_workspace.logs.id
  }
}
