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
    workload_identities = {
      for k in keys(var.workload_identities) : k => {
        id       = var.workload_identity_ids[k]
        subjects = [for key, fc in azurerm_federated_identity_credential.workloads : fc.subject if local.federated_credentials[key].identity == k]
      }
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
