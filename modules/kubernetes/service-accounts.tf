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

# Agents - no cloud identity
# --------------------------
# ServiceAccount = role, pod = run (ADR-003).
# No automounted API token. Pods mount a projected token with audience `token-broker` instead.

resource "kubernetes_service_account_v1" "agents" {
  for_each = toset(var.agent_roles)

  metadata {
    name      = each.value
    namespace = kubernetes_namespace_v1.ns["agents"].metadata[0].name
  }

  automount_service_account_token = false
}
