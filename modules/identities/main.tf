# =================
#  Resource Group
# =================
# Identity principals and grants must survive cluster resource group deletion.

resource "azurerm_resource_group" "identities_rg" {
  name     = "${local.name}-identities-rg"
  location = var.location
  tags     = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  name          = lower(var.name)
  name_suffixed = "${local.name}-${var.suffix}"
}
