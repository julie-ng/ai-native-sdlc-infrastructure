variable "workload_identities" {
  type = map(object({
    namespace        = string
    service_accounts = list(string)
  }))
  description = "Same map as the cluster module. Namespaces must be in local.namespaces."
}

variable "workload_client_ids" {
  type        = map(string)
  description = "Managed identity client ID per workload identity key, from the identities module."
}

variable "agent_roles" {
  type        = list(string)
  description = "One ServiceAccount per agent role in the `agents` namespace."
}

variable "platform_namespace" {
  type        = string
  description = "Namespace for platform services."
}

variable "argo_namespace" {
  type        = string
  description = "Namespace for the Argo Workflows controller and server."
}

variable "github_broker_namespace" {
  type        = string
  description = "Namespace for the GitHub token broker."
}
