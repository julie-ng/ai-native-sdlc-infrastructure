output "summary" {
  value = {
    resource_group = {
      name     = azurerm_resource_group.cluster_rg.name
      location = azurerm_resource_group.cluster_rg.location
    }
    aks_cluster = {
      name            = azurerm_kubernetes_cluster.aks.name
      id              = azurerm_kubernetes_cluster.aks.id
      fqdn            = azurerm_kubernetes_cluster.aks.fqdn
      node_rg         = azurerm_kubernetes_cluster.aks.node_resource_group
      oidc_issuer_url = azurerm_kubernetes_cluster.aks.oidc_issuer_url
    }
    managed_identities = {
      control_plane = {
        name         = azurerm_user_assigned_identity.control_plane_mi.name
        client_id    = azurerm_user_assigned_identity.control_plane_mi.client_id
        principal_id = azurerm_user_assigned_identity.control_plane_mi.principal_id
      }
      kubelet = {
        name         = azurerm_user_assigned_identity.kubelet_mi.name
        client_id    = azurerm_user_assigned_identity.kubelet_mi.client_id
        principal_id = azurerm_user_assigned_identity.kubelet_mi.principal_id
      }
    }
    workload_identities = {
      for k, mi in azurerm_user_assigned_identity.workloads : k => {
        name      = mi.name
        client_id = mi.client_id
        subjects  = [for key, fc in azurerm_federated_identity_credential.workloads : fc.subject if local.federated_credentials[key].identity == k]
      }
    }
  }
}

output "workload_identities" {
  value = {
    for k, mi in azurerm_user_assigned_identity.workloads : k => {
      name      = mi.name
      client_id = mi.client_id
    }
  }
}

# For the kubernetes provider. kube_config is sensitive as a whole.
output "kube_api" {
  value = {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    cluster_ca_certificate = azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate
  }
  sensitive = true
}
