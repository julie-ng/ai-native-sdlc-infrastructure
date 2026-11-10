# =========================
# Platform Service Secrets
# =========================
# CSI reads values at pod mount time; reuse the existing secret-scoped identity grants.
resource "kubernetes_manifest" "platform_services_secrets" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = var.platform_services_secret_provider_class_name
      namespace = kubernetes_namespace_v1.ns[var.platform_namespace].metadata[0].name
    }
    spec = {
      provider = "azure"
      parameters = {
        usePodIdentity = "false"
        clientID       = var.workload_client_ids["platform-services"]
        keyvaultName   = var.key_vault_name
        tenantId       = var.key_vault_tenant_id
        objects = yamlencode({
          array = [for secret_name in [
            var.key_vault_secret_names.platform_services_admin_token,
            var.key_vault_secret_names.platform_services_hmac_key,
            ] : yamlencode({
              objectName    = secret_name
              objectType    = "secret"
              objectVersion = ""
          })]
        })
      }
    }
  }
}
