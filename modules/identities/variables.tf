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
  description = "Names of platform services requiring separate managed identities."

  validation {
    condition     = alltrue([for k in ["artifact-service", "token-broker", "argo-workflow-controller", "argo-server"] : contains(var.workload_identities, k)])
    error_message = "Must include artifact-service, token-broker, argo-workflow-controller and argo-server; persistent grants reference them."
  }
}
