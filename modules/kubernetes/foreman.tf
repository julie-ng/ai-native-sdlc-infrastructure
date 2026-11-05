# =====================
# Trusted Run Bootstrap
# =====================
# foreman uses the platform ServiceAccount/federation map, not agent_roles.
# RBAC cannot restrict create by Secret name; this trusted step can create any Secret in agents.
resource "kubernetes_role_v1" "foreman" {
  metadata {
    name      = "foreman"
    namespace = kubernetes_namespace_v1.ns[var.agents_namespace].metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["create"]
  }
}

resource "kubernetes_role_binding_v1" "foreman" {
  metadata {
    name      = "foreman"
    namespace = kubernetes_namespace_v1.ns[var.agents_namespace].metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.foreman.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.platform["${var.agents_namespace}/foreman"].metadata[0].name
    namespace = kubernetes_namespace_v1.ns[var.agents_namespace].metadata[0].name
  }
}

# CSI reads the value at pod mount time; Terraform manages references only.
resource "kubernetes_manifest" "foreman_admin_token" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = var.foreman_secret_provider_class_name
      namespace = kubernetes_namespace_v1.ns[var.agents_namespace].metadata[0].name
    }
    spec = {
      provider = "azure"
      parameters = {
        usePodIdentity = "false"
        clientID       = var.workload_client_ids["foreman"]
        keyvaultName   = var.key_vault_name
        tenantId       = var.key_vault_tenant_id
        objects = yamlencode({
          array = [yamlencode({
            objectName    = var.key_vault_secret_names.platform_services_admin_token
            objectType    = "secret"
            objectVersion = ""
          })]
        })
      }
    }
  }
}
