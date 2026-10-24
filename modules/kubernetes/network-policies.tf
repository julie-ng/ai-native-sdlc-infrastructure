# ==================
#  Network Policies
# ==================
# Enforced by Cilium (cluster module). Issue #4.

# Agents - no IMDS
# ----------------
# IMDS hands any non-hostNetwork pod tokens for every identity attached to its node, e.g. the
# kubelet identity (AcrPull). Blocking it keeps ADR-003 independent of what those identities can do.
#
# NetworkPolicy only allows, so this allows all egress except IMDS. Cilium's ipBlock can't select
# pod or node IPs, hence the separate all-namespaces peer for kube-dns and in-cluster services:
# https://learn.microsoft.com/en-us/azure/aks/azure-cni-powered-by-cilium#why-is-traffic-being-blocked-when-the-networkpolicy-has-an-ipblock-that-allows-the-ip-address
#
# Enforces: no IMDS from non-hostNetwork agent pods. Does not restrict any other egress. Pod
# Security baseline (namespaces.tf) rejects the hostNetwork pods this can't cover.

resource "kubernetes_network_policy_v1" "agents_deny_imds" {
  metadata {
    name      = "deny-imds"
    namespace = kubernetes_namespace_v1.ns["agents"].metadata[0].name
  }

  spec {
    pod_selector {} # every pod in the namespace
    policy_types = ["Egress"]

    egress {
      to {
        ip_block {
          cidr   = "0.0.0.0/0"
          except = ["169.254.169.254/32"]
        }
      }

      # Empty selector = all namespaces (kubernetes provider v3.4.0 kubernetes/structure_label_selector.go)
      to {
        namespace_selector {}
      }
    }
  }
}
