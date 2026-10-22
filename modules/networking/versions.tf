terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.10, < 6.0" # 5.x argument names, e.g. node_provisioning_profile
    }
  }
}
