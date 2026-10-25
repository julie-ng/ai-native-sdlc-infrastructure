# =============
#  AKS Cluster
# =============

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${local.name_suffixed}-cluster"
  location            = azurerm_resource_group.cluster_rg.location
  resource_group_name = azurerm_resource_group.cluster_rg.name
  node_resource_group = "${local.name}-aks-managed-rg" # instead of default MC_ prefix
  dns_prefix          = local.name_suffixed
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"
  tags                = var.tags

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Identity & access - Entra ID only, Azure RBAC for Kubernetes authorization
  local_account_disabled            = true
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.control_plane_identity.id]
  }

  kubelet_identity {
    client_id                 = var.kubelet_identity.client_id
    object_id                 = var.kubelet_identity.principal_id
    user_assigned_identity_id = var.kubelet_identity.id
  }

  # Node pools are defined explicitly - no node auto-provisioning
  node_provisioning_profile {
    mode = "Manual"
  }

  # System pool. User pools are separate resources, see _node-pools.tf
  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_vm_size
    os_sku                       = "AzureLinux"
    vnet_subnet_id               = var.aks_nodes_subnet_id
    auto_scaling_enabled         = true
    min_count                    = var.system_nodes_min_count
    max_count                    = var.system_nodes_max_count
    only_critical_addons_enabled = true # taint: keep platform services and agents off the system pool
    temporary_name_for_rotation  = "systemtmp"
    tags                         = var.tags

    upgrade_settings {
      max_surge = "1"
    }
  }

  # Public API server (default). CNI Overlay with Cilium as data plane and network policy engine,
  # needed for the agents IMDS NetworkPolicy (kubernetes/network-policies.tf, issue #4).
  # Switching from the azure data plane is in place but reimages all pools; switching back forces
  # cluster replacement (azurerm v5.10.0 internal/services/containers/kubernetes_cluster_resource.go).
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"

    # Fixed egress IP from the networking module, instead of an AKS-managed one
    load_balancer_profile {
      outbound_ip_address_ids = [var.egress_ip_id]
    }
  }

  # Key Vault secrets as mounted files (Secrets Store CSI driver)
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  # Container Insights, managed identity auth. Needs the data collection rule in _monitoring.tf
  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,           # autoscaler
      default_node_pool[0].orchestrator_version, # automatic upgrades
      kubernetes_version,                        # automatic upgrades
    ]
  }
}
