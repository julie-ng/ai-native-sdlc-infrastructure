# ==================
#  Service Accounts
# ==================

# Platform services - workload identity
# -------------------------------------
# Pods also need the label `azure.workload.identity/use: "true"` - set in their own manifests.

locals {
  platform_service_accounts = merge([
    for key, wi in var.workload_identities : {
      for sa in wi.service_accounts : "${wi.namespace}/${sa}" => {
        identity  = key
        namespace = wi.namespace
        name      = sa
      }
    }
  ]...)
}

resource "kubernetes_service_account_v1" "platform" {
  for_each = local.platform_service_accounts

  metadata {
    name      = each.value.name
    namespace = kubernetes_namespace_v1.ns[each.value.namespace].metadata[0].name
    annotations = {
      "azure.workload.identity/client-id" = var.workload_client_ids[each.value.identity]
    }
  }
}

# Agents - secret-read identities for planner and coder (#26)
# --------------------------
# ServiceAccount = role, pod = run (ADR-003).
# No automounted API token. Broker auth uses a projected token with audience `token-broker`.
# Pods mounting CSI secrets opt into Azure workload identity in their manifests.

resource "kubernetes_service_account_v1" "agents" {
  for_each = toset(var.agent_roles)

  metadata {
    name      = each.value
    namespace = kubernetes_namespace_v1.ns[var.agents_namespace].metadata[0].name
    annotations = contains(keys(var.agent_secret_provider_class_names), each.value) ? {
      "azure.workload.identity/client-id" = var.workload_client_ids[each.value]
    } : {}
  }

  automount_service_account_token = false
}
