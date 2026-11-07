# =====================
# Agent Secret Mounts
# =====================
# CSI reads the value at pod mount time; Terraform manages references only.
locals {
  agent_secret_names = {
    coder = [
      var.key_vault_secret_names.agent_gpg_private_key,
      var.key_vault_secret_names.julieio_goose_github_pat,
      var.key_vault_secret_names.vercel_ai_gateway_api_key,
    ]
    planner = [
      var.key_vault_secret_names.julieio_goose_github_pat,
      var.key_vault_secret_names.vercel_ai_gateway_api_key,
    ]
  }
}

resource "kubernetes_manifest" "agent_secrets" {
  for_each = var.agent_secret_provider_class_names

  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = each.value
      namespace = kubernetes_namespace_v1.ns[var.agents_namespace].metadata[0].name
    }
    spec = {
      provider = "azure"
      parameters = {
        usePodIdentity = "false"
        clientID       = var.workload_client_ids[each.key]
        keyvaultName   = var.key_vault_name
        tenantId       = var.key_vault_tenant_id
        objects = yamlencode({
          array = [for secret_name in local.agent_secret_names[each.key] : yamlencode({
            objectName    = secret_name
            objectType    = "secret"
            objectVersion = ""
          })]
        })
      }
    }
  }
}
