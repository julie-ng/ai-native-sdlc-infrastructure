variable "name" {
  type        = string
  description = "Base name for all resources."
}

variable "suffix" {
  type        = string
  description = "Appended to cluster resources and workload identities."
}

variable "location" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# AKS
# ---

variable "kubernetes_version" {
  type        = string
  description = "null = AKS default version for the region."
  default     = null
}

variable "pod_cidr" {
  type = string
}

variable "service_cidr" {
  type = string
}

variable "dns_service_ip" {
  type = string
}

# Node pools
# ----------

variable "system_vm_size" {
  type = string
}

variable "system_nodes_min_count" {
  type = number
}

variable "system_nodes_max_count" {
  type = number
}

variable "platform_vm_size" {
  type = string
}

variable "platform_nodes_min_count" {
  type = number
}

variable "platform_nodes_max_count" {
  type = number
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

variable "log_analytics_workspace_id" {
  type = string
}

variable "container_registry_id" {
  type = string
}

variable "key_vault_id" {
  type = string
}

variable "artifacts_container_id" {
  type = string
}

# Workload identities
# -------------------

variable "workload_identities" {
  type = map(object({
    namespace        = string
    service_accounts = list(string)
  }))
  description = "Managed identity per key, federated credential per service account."

  validation {
    condition     = alltrue([for k in ["artifact-service", "token-broker"] : contains(keys(var.workload_identities), k)])
    error_message = "Must include artifact-service and token-broker - role assignments in _rbac.tf reference them."
  }
}
