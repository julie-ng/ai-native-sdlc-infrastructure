# ==========================
#  GitHub Workflow Identity
# ==========================

resource "azurerm_user_assigned_identity" "stop" {
  name                = var.settings.identity_name
  resource_group_name = data.azurerm_resource_group.identities.name
  location            = data.azurerm_resource_group.identities.location
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_federated_identity_credential" "github" {
  name                      = "platform-stop"
  user_assigned_identity_id = azurerm_user_assigned_identity.stop.id
  issuer                    = var.settings.issuer
  audience                  = [var.settings.audience]
  subject                   = var.settings.subject
}
