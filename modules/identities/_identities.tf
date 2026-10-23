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
