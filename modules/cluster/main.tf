# ================
#  Resource Group
# ================

resource "azurerm_resource_group" "cluster_rg" {
  name     = "${local.name_suffixed}-rg"
  location = var.location
  tags     = var.tags
}

# ================
#  Normalized Vars
# ================

locals {
  name          = lower(var.name)
  name_suffixed = "${local.name}-${var.suffix}"
}

data "azurerm_client_config" "current" {}
