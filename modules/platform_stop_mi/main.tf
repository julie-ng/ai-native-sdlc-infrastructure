# ===================
#  Existing Resources
# ===================

# The identities module retains ownership of this persistent group.
data "azurerm_resource_group" "identities" {
  name = var.resource_group_name
}

data "azurerm_client_config" "current" {}
