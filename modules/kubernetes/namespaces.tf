# ============
#  Namespaces
# ============
# ADR-003: platform services, Argo and the broker are trusted; agents are not.

locals {
  namespaces = [var.platform_namespace, var.argo_namespace, var.github_broker_namespace, "agents"]
}

resource "kubernetes_namespace_v1" "ns" {
  for_each = toset(local.namespaces)

  metadata {
    name = each.value
  }
}
