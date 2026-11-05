# =====================
# Agent Commit Signing
# =====================
# CSI reads the value at pod mount time; Terraform manages references only.
resource "kubernetes_manifest" "coder_gpg_key" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = var.coder_secret_provider_class_name
      namespace = kubernetes_namespace_v1.ns[var.agents_namespace].metadata[0].name
    }
    spec = {
      provider = "azure"
      parameters = {
        usePodIdentity = "false"
        clientID       = var.coder_client_id
        keyvaultName   = var.key_vault_name
        tenantId       = var.key_vault_tenant_id
        objects = yamlencode({
          array = [yamlencode({
            objectName    = var.key_vault_secret_names.agent_gpg_private_key
            objectType    = "secret"
            objectVersion = ""
          })]
        })
      }
    }
  }
}
