# =====================
#  Workload Identities
# =====================
# Platform services only (ADR-003). One managed identity per service,
# one federated credential per Kubernetes ServiceAccount it runs as.

locals {
  federated_credentials = merge([
    for key, wi in var.workload_identities : {
      for sa in wi.service_accounts : "${key}/${sa}" => {
        identity        = key
        namespace       = wi.namespace
        service_account = sa
      }
    }
  ]...)
}

resource "azurerm_federated_identity_credential" "workloads" {
  for_each                  = local.federated_credentials
  name                      = "${each.value.namespace}-${each.value.service_account}"
  user_assigned_identity_id = var.workload_identity_ids[each.value.identity]
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject                   = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}
