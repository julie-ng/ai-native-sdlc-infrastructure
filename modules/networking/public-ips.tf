# ============
#  Static IPs
# ============
# Outlive the cluster, so allowlists and DNS records stay valid across rebuilds.

# Ingress - reserved only. No ingress controller and no role assignments yet.
resource "azurerm_public_ip" "ingress" {
  name                = "${local.name}-ingress-ip"
  resource_group_name = azurerm_resource_group.networking_rg.name
  location            = azurerm_resource_group.networking_rg.location
  sku                 = "Standard"
  allocation_method   = "Static"
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# Egress - outbound IP of the cluster load balancer.
# Allowlisted on the Postgres firewall.
resource "azurerm_public_ip" "egress" {
  name                = "${local.name}-egress-ip"
  resource_group_name = azurerm_resource_group.networking_rg.name
  location            = azurerm_resource_group.networking_rg.location
  sku                 = "Standard"
  allocation_method   = "Static"
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}
