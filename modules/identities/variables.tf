variable "name" {
  type        = string
  description = "Base name for all resources."
}

variable "location" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# From networking module
# ----------------------

variable "aks_nodes_subnet_id" {
  type = string
}

variable "egress_ip_id" {
  type = string
}

# From shared module
# ------------------

variable "container_registry_id" {
  type = string
}

variable "key_vault_id" {
  type = string
}

variable "artifacts_container_id" {
  type = string
}

variable "artifacts_storage_account_id" {
  type        = string
  description = "Scope for Storage Blob Delegator - user delegation keys are account-level."
}

variable "argo_container_id" {
  type = string
}

# Workload identities
# -------------------

variable "workload_identities" {
  type        = set(string)
  description = "Workload identity names, including the dedicated agent-signing identity (ADR-003)."

  validation {
    condition     = alltrue([for k in ["platform-services", "foreman", "gh-token-broker", "argo-workflow-controller", "argo-server", "agent-signing"] : contains(var.workload_identities, k)])
    error_message = "Must include platform-services, foreman, gh-token-broker, argo-workflow-controller, argo-server and agent-signing; persistent grants reference them."
  }
}

variable "key_vault_secret_names" {
  type = object({
    platform_services_admin_token   = string
    platform_services_hmac_key      = string
    token_broker_gh_app_private_key = string
    agent_gpg_private_key           = string
  })
  description = "Existing Key Vault secret names for secret-scoped grants and CSI mounts. Values are populated outside Terraform."
}
