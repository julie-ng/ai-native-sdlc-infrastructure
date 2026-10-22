# =======
#  Setup
# =======
# State is local for now. Subscription comes from the environment:
#   export ARM_SUBSCRIPTION_ID=…

terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
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

provider "azurerm" {
  storage_use_azuread = true # shared keys are disabled on the storage account
  features {}
}

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
