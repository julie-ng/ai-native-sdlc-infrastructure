# ============
#  Node Pools
# ============
# POC pools keep at least one node each; scale-to-zero is deferred.

resource "azurerm_kubernetes_cluster_node_pool" "platform" {
  name                  = "platform"
  mode                  = "User"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.platform_vm_size
  os_sku                = "AzureLinux"
  vnet_subnet_id        = var.aks_nodes_subnet_id
  auto_scaling_enabled  = true
  min_count             = var.platform_nodes_min_count
  max_count             = var.platform_nodes_max_count
  tags                  = var.tags

  upgrade_settings {
    max_surge = "1"
  }

  lifecycle {
    ignore_changes = [
      node_count,           # autoscaler
      orchestrator_version, # automatic upgrades
    ]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "agents" {
  name                  = "agents"
  mode                  = "User"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.agents_vm_size
  os_sku                = "AzureLinux"
  vnet_subnet_id        = var.aks_nodes_subnet_id
  auto_scaling_enabled  = true
  min_count             = var.agents_nodes_min_count
  max_count             = var.agents_nodes_max_count
  # Keep platform workloads off agent nodes; agent templates must tolerate this taint.
  node_taints = ["workload=agents:NoSchedule"]
  tags        = var.tags

  upgrade_settings {
    max_surge = "1"
  }

  lifecycle {
    ignore_changes = [
      node_count,           # autoscaler
      orchestrator_version, # automatic upgrades
    ]
  }
}
