# ====================
#  Cluster Identities
# ====================

# Control plane - manages cluster resources: load balancer, node VMs, subnet joins
resource "azurerm_user_assigned_identity" "control_plane_mi" {
  name                = "${local.name}-control-plane-mi"
  resource_group_name = azurerm_resource_group.identities_rg.name
  location            = azurerm_resource_group.identities_rg.location
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# Kubelet - pulls images from the registry
resource "azurerm_user_assigned_identity" "kubelet_mi" {
  name                = "${local.name}-kubelet-mi"
  resource_group_name = azurerm_resource_group.identities_rg.name
  location            = azurerm_resource_group.identities_rg.location
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# ============================================
#  GitHub Federated Credential (agent-images)
# ============================================
#  Used to push images to Azure Container Registry

resource "azurerm_user_assigned_identity" "github_agent_images_mi" {
  name                = "ai-sdlc-agent-images-github-push-mi"
  resource_group_name = azurerm_resource_group.identities_rg.name
  location            = azurerm_resource_group.identities_rg.location
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# MSFT How-to - https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust-user-assigned-managed-identity
# Configuration values - https://docs.github.com/en/actions/reference/security/oidc
resource "azurerm_federated_identity_credential" "github_agent_images_prod_environment" {
  name                      = "ai-sdlc-github-push-agent-images"
  audience                  = ["api://AzureADTokenExchange"]                # per MSFT docs
  issuer                    = "https://token.actions.githubusercontent.com" # per GitHub Docs
  user_assigned_identity_id = azurerm_user_assigned_identity.github_agent_images_mi.id
  subject                   = "repo:julie-ng@1269507/ai-native-sdlc-agent-images@1428424091:environment:production" # immutable subject claim
}

# =================================================
#  GitHub Federated Credential (platform-services)
# =================================================
#  Used to push images to Azure Container Registry
#
resource "azurerm_user_assigned_identity" "github_platform_services_mi" {
  name                = "ai-sdlc-platform-services-github-push-mi"
  resource_group_name = azurerm_resource_group.identities_rg.name
  location            = azurerm_resource_group.identities_rg.location
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# MSFT How-to - https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust-user-assigned-managed-identity
# Configuration values - https://docs.github.com/en/actions/reference/security/oidc
resource "azurerm_federated_identity_credential" "github_platform_services_prod_environment" {
  name                      = "ai-sdlc-github-push-platform-services"
  audience                  = ["api://AzureADTokenExchange"]                # per MSFT docs
  issuer                    = "https://token.actions.githubusercontent.com" # per GitHub Docs
  user_assigned_identity_id = azurerm_user_assigned_identity.github_platform_services_mi.id
  subject                   = "repo:julie-ng@1269507/ai-native-sdlc-platform-services@1431106684:environment:production" # immutable subject claim
}
