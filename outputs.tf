output "cluster" {
  description = "Cluster details available before the Kubernetes module is applied."
  value       = module.cluster.summary
}

output "summary" {
  value = {
    suffix     = local.suffix
    networking = module.networking
    shared     = module.shared
    identities = module.identities
    cluster    = module.cluster.summary
    kubernetes = module.kubernetes
  }
}

output "github_shutdown" {
  description = "Repository Actions variables for the shutdown workflow; identifiers only, no credentials."
  value = {
    AZURE_CLIENT_ID            = module.github_shutdown.identity.client_id
    AZURE_TENANT_ID            = module.github_shutdown.identity.tenant_id
    AZURE_SUBSCRIPTION_ID      = module.github_shutdown.identity.subscription_id
    AKS_RESOURCE_GROUP         = module.cluster.summary.resource_group.name
    AKS_CLUSTER_NAME           = module.cluster.summary.aks_cluster.name
    AZ_POSTGRES_RESOURCE_GROUP = module.shared.resource_group.name
    AZ_POSTGRES_SERVER_NAME    = module.shared.postgres.name
  }
}
