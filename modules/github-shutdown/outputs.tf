output "identity" {
  value = {
    client_id       = azurerm_user_assigned_identity.shutdown.client_id
    tenant_id       = azurerm_user_assigned_identity.shutdown.tenant_id
    subscription_id = data.azurerm_client_config.current.subscription_id
  }
}
