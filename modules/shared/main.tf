# ================
#  Resource Group
# ================
# Longer lifecycle than the cluster - no suffix on the group.
# Resources that need globally unique names carry the suffix.

resource "azurerm_resource_group" "shared_rg" {
  name     = "${local.name}-shared-rg"
  location = var.location
  tags     = var.tags
}

# ================
#  Normalized Vars
# ================

locals {
  name          = lower(var.name)
  name_suffixed = "${local.name}-${var.suffix}"
  name_squished = replace(local.name_suffixed, "-", "") # storage account, registry: alphanumeric only

  # Storage account IP rules reject /31 and /32 CIDRs - plain address instead
  storage_ip_rules = [for cidr in var.admin_ip_ranges : trimsuffix(cidr, "/32")]
}

data "azurerm_client_config" "current" {}
