variable "resource_group_name" {
  type        = string
  description = "Existing identities resource group; this module does not own it."
}

variable "settings" {
  type = object({
    identity_name = string
    issuer        = string
    audience      = string
    subject       = string
    aks_role      = string
    postgres_role = string
  })
  description = "Platform stop identity, federation trust and built-in roles."
}

variable "aks_cluster_id" {
  type        = string
  description = "Exact AKS resource scope for the stop role."
}

variable "postgres_server_id" {
  type        = string
  description = "Exact PostgreSQL Flexible Server scope for the stop role."
}

variable "tags" {
  type = map(string)
}
