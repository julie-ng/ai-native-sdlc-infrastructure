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

variable "vnet_address_space" {
  type = list(string)
}

variable "aks_nodes_address_prefixes" {
  type = list(string)
}

variable "firewall_address_prefixes" {
  type = list(string)
}
