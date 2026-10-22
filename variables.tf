# ======
#  Core
# ======

variable "name" {
  type        = string
  description = "Base name for all resources, e.g. `ai-sdlc`."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.name))
    error_message = "Lowercase alphanumeric, 2-10 characters. Squashed into storage account and registry names, which allow no dashes."
  }
}

variable "suffix" {
  type        = string
  description = "Fixed suffix for globally unique names. Empty = random 4-character suffix, kept in state."
  default     = ""
}

variable "location" {
  type        = string
  description = "Azure region for all resources."
}

variable "default_tags" {
  type = map(string)
}

# ==============
#  Admin Access
# ==============

variable "admin_ip_ranges" {
  type        = list(string)
  description = "CIDRs allowed through Key Vault, Storage and Postgres firewalls, e.g. the admin's home IP as x.x.x.x/32. Empty = only the cluster."
  default     = []
}

# ============
#  Networking
# ============

variable "vnet_address_space" {
  type = list(string)
}

variable "aks_nodes_address_prefixes" {
  type = list(string)
}

variable "firewall_address_prefixes" {
  type        = list(string)
  description = "Reserved for Azure Firewall. Subnet is created empty, no firewall deployed."
}

variable "pod_cidr" {
  type        = string
  description = "CNI Overlay pod range. Must not overlap the VNet or service CIDR."
}

variable "service_cidr" {
  type        = string
  description = "Kubernetes service range. Must not overlap the VNet or pod CIDR."
}

variable "dns_service_ip" {
  type        = string
  description = "Inside service_cidr, not the first address."
}

# =====
#  AKS
# =====

variable "kubernetes_version" {
  type        = string
  description = "null = AKS default version for the region."
  default     = null
}

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

variable "agent_roles" {
  type        = list(string)
  description = "One ServiceAccount per agent role in the `agents` namespace (ADR-003)."
}

# ==========
#  Postgres
# ==========

variable "postgres_version" {
  type = string
}

variable "postgres_sku_name" {
  type = string
}

variable "postgres_databases" {
  type        = list(string)
  description = "One server, separate databases (ADR-005)."
}
