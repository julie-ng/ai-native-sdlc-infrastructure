# ====================
# GitHub Token Broker
# ====================
# CSI reads the value at pod mount time; Terraform manages references only.
resource "kubernetes_manifest" "github_broker_secrets" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = var.github_broker_secret_provider_class_name
      namespace = kubernetes_namespace_v1.ns[var.github_broker_namespace].metadata[0].name
    }
    spec = {
      provider = "azure"
      parameters = {
        usePodIdentity = "false"
        clientID       = var.workload_client_ids["gh-token-broker"]
        keyvaultName   = var.key_vault_name
        tenantId       = var.key_vault_tenant_id
        objects = yamlencode({
          array = [yamlencode({
            objectName    = var.key_vault_secret_names.token_broker_gh_app_private_key
            objectType    = "secret"
            objectVersion = ""
          })]
        })
      }
    }
  }
}

# TokenReview is cluster-scoped; auth-delegator would also grant SubjectAccessReview.
resource "kubernetes_cluster_role_v1" "token_broker" {
  metadata {
    name = "token-broker"
  }
  rule {
    api_groups = ["authentication.k8s.io"]
    resources  = ["tokenreviews"]
    verbs      = ["create"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "token_broker" {
  metadata {
    name = "token-broker"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.token_broker.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.platform["${var.github_broker_namespace}/token-broker"].metadata[0].name
    namespace = kubernetes_namespace_v1.ns[var.github_broker_namespace].metadata[0].name
  }
}

# The broker looks up the bound pod, without listing other pods or reading Secrets.
resource "kubernetes_role_v1" "token_broker" {
  metadata {
    name      = "token-broker"
    namespace = kubernetes_namespace_v1.ns[var.agents_namespace].metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get"]
  }
}

resource "kubernetes_role_binding_v1" "token_broker" {
  metadata {
    name      = "token-broker"
    namespace = kubernetes_namespace_v1.ns[var.agents_namespace].metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.token_broker.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.platform["${var.github_broker_namespace}/token-broker"].metadata[0].name
    namespace = kubernetes_namespace_v1.ns[var.github_broker_namespace].metadata[0].name
  }
}
