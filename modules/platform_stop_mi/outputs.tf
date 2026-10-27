output "identity" {
  value = {
    client_id       = azurerm_user_assigned_identity.stop.client_id
    tenant_id       = azurerm_user_assigned_identity.stop.tenant_id
    subscription_id = data.azurerm_client_config.current.subscription_id
  }
}
