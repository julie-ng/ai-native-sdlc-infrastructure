variable "name" {
  type        = string
  description = "Base name for all resources."
}

variable "suffix" {
  type        = string
  description = "Appended to resources that need globally unique names."
}

variable "location" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# Network access
# --------------

variable "aks_nodes_subnet_id" {
  type        = string
  description = "Allowed via service endpoint on Key Vault and Storage."
}

variable "egress_ip_address" {
  type        = string
  description = "Cluster outbound IP, allowed on the Postgres firewall."
}

variable "admin_ip_ranges" {
  type        = list(string)
  description = "CIDRs allowed on Key Vault, Storage and Postgres."
  default     = []
}

# Postgres
# --------

variable "postgres_version" {
  type = string
}

variable "postgres_sku_name" {
  type = string
}

variable "postgres_databases" {
  type = list(string)
}
