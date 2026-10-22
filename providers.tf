# =======
#  Setup
# =======
# State is local for now.
# Authenticates via the Azure CLI session - no stored credentials, no hard-coded IDs.
# Tenant, subscription and deployer identity come from `az login` / `az account set`.

terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}

# No subscription_id: with CLI auth (use_cli, the default) the provider uses
# the subscription selected by `az account set`.
provider "azurerm" {
  storage_use_azuread = true # shared keys are disabled on the storage account
  features {}
}

# Only used to look up the deployer's UPN for the Postgres Entra admin
provider "azuread" {}

# Local accounts are disabled on the cluster, so authenticate via Entra ID.
# Requires `kubelogin` and an `az login` session on the machine running Terraform.
# Only usable once the cluster exists - see README for apply order.
provider "kubernetes" {
  host                   = module.cluster.kube_api.host
  cluster_ca_certificate = base64decode(module.cluster.kube_api.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args = [
      "get-token",
      "--login", "azurecli",
      "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630" # AKS Entra server app ID, same in every tenant
    ]
  }
}
