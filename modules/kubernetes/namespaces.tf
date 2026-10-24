# ============
#  Namespaces
# ============
# ADR-003: platform services, Argo and the broker are trusted; agents are not.

locals {
  namespaces = ["platform", "argo", "github-broker", "agents"]

  # Pod Security Admission. Agents run LLM-driven code: baseline rejects hostNetwork and privileged
  # pods, which bypass the IMDS NetworkPolicy (network-policies.tf). restricted is warn/audit only,
  # to surface what agent templates would need before enforcing it.
  namespace_labels = {
    agents = {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }
}

resource "kubernetes_namespace_v1" "ns" {
  for_each = toset(local.namespaces)

  metadata {
    name   = each.value
    labels = lookup(local.namespace_labels, each.value, null)
  }
}
