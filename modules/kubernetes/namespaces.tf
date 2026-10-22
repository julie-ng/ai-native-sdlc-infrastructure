# ============
#  Namespaces
# ============
# ADR-003: platform services, Argo and the broker are trusted; agents are not.

locals {
  namespaces = ["platform", "argo", "github-broker", "agents"]
}

resource "kubernetes_namespace_v1" "ns" {
  for_each = toset(local.namespaces)

  metadata {
    name = each.value
  }
}
