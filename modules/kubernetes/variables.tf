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
  description = "One ServiceAccount per agent role in the agents namespace."
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

variable "agents_namespace" {
  type        = string
  description = "Namespace for agent pods. Pod Security baseline and the IMDS NetworkPolicy apply here."
}

variable "azure_imds_endpoint" {
  type        = string
  description = "Azure Instance Metadata Service IP, blocked for agent pods. Owned by Azure."
}

variable "key_vault_secret_names" {
  type = object({
    platform_services_admin_token   = string
    platform_services_hmac_key      = string
    token_broker_gh_app_private_key = string
  })
  description = "Existing Key Vault secret names for secret-scoped grants and CSI mounts. Values are populated outside Terraform."
}

variable "key_vault_name" {
  type = string
}

variable "key_vault_tenant_id" {
  type        = string
  description = "Tenant owning the vault, from the shared module."
}

variable "foreman_secret_provider_class_name" {
  type        = string
  description = "SecretProviderClass name referenced by the trusted foreman workflow volume in the agents namespace."
}
