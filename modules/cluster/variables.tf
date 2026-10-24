variable "name" {
  type        = string
  description = "Base name for all resources."
}

variable "suffix" {
  type        = string
  description = "Appended to cluster resources."
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

variable "agents_vm_size" {
  type = string
}

variable "agents_nodes_min_count" {
  type = number
}

variable "agents_nodes_max_count" {
  type = number
}

# Monitoring
# ----------

variable "platform_namespace" {
  type        = string
  description = "Platform namespace, for Container Insights namespace filtering."
}

variable "argo_namespace" {
  type        = string
  description = "Argo namespace, for Container Insights namespace filtering."
}

variable "github_broker_namespace" {
  type        = string
  description = "GitHub broker namespace, for Container Insights namespace filtering."
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

# Workload identities
# -------------------

variable "workload_identities" {
  type = map(object({
    namespace        = string
    service_accounts = list(string)
  }))
  description = "ServiceAccounts trusted by each platform workload identity."
}

# From identities module
# ----------------------

variable "control_plane_identity" {
  type = object({
    id           = string
    name         = string
    client_id    = string
    principal_id = string
  })
}

variable "kubelet_identity" {
  type = object({
    id           = string
    name         = string
    client_id    = string
    principal_id = string
  })
}

variable "workload_identity_ids" {
  type = map(string)
}
