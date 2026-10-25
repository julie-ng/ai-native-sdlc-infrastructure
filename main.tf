# Suffix to avoid errors on Azure resources that require globally unique names.
resource "random_string" "suffix" {
  length      = 4
  min_lower   = 2
  min_numeric = 1
  special     = false
  upper       = false
  numeric     = true
}

locals {
  suffix = var.suffix == "" ? random_string.suffix.result : var.suffix
}

# Apply one module at a time, in this order - see README.
#   1. networking
#   2. shared      (backing services)
#   3. identities   (persistent principals and grants)
#   4. cluster
#   5. kubernetes  (in-cluster resources)

# ============
#  Networking
# ============

module "networking" {
  source   = "./modules/networking"
  name     = var.name
  location = var.location
  tags     = var.default_tags

  vnet_address_space         = var.vnet_address_space
  aks_nodes_address_prefixes = var.aks_nodes_address_prefixes
  firewall_address_prefixes  = var.firewall_address_prefixes
}

# ======================
#  Shared Infrastructure
# ======================
# Backing services: database, blob storage, key vault, registry, log analytics

module "shared" {
  source   = "./modules/shared"
  name     = var.name
  suffix   = local.suffix
  location = var.location
  tags     = var.default_tags

  # Network access via service endpoint (Key Vault, Storage) and egress IP (Postgres)
  aks_nodes_subnet_id = module.networking.subnets.aks_nodes.id
  egress_ip_address   = module.networking.public_ips.egress.ip_address
  admin_ip_ranges     = var.admin_ip_ranges

  # Postgres
  postgres_version   = var.postgres_version
  postgres_sku_name  = var.postgres_sku_name
  postgres_databases = var.postgres_databases
}

# ======================
#  Persistent Identities
# ======================

module "identities" {
  source   = "./modules/identities"
  name     = var.name
  location = var.location
  tags     = var.default_tags

  aks_nodes_subnet_id          = module.networking.subnets.aks_nodes.id
  egress_ip_id                 = module.networking.public_ips.egress.id
  container_registry_id        = module.shared.container_registry.id
  key_vault_id                 = module.shared.key_vault.id
  artifacts_container_id       = module.shared.storage.artifacts.container_id
  artifacts_storage_account_id = module.shared.storage.artifacts.id
  argo_container_id            = module.shared.storage.argo.container_id

  workload_identities = toset(keys(local.workload_identities))
}

# =============
#  AKS Cluster
# =============

module "cluster" {
  source   = "./modules/cluster"
  name     = var.name
  suffix   = local.suffix
  location = var.location
  tags     = var.default_tags

  # AKS
  kubernetes_version = var.kubernetes_version
  pod_cidr           = var.pod_cidr
  service_cidr       = var.service_cidr
  dns_service_ip     = var.dns_service_ip

  # Node pools
  system_vm_size         = var.system_vm_size
  system_nodes_min_count = var.system_nodes_min_count
  system_nodes_max_count = var.system_nodes_max_count

  platform_vm_size         = var.platform_vm_size
  platform_nodes_min_count = var.platform_nodes_min_count
  platform_nodes_max_count = var.platform_nodes_max_count

  agents_vm_size         = var.agents_vm_size
  agents_nodes_min_count = var.agents_nodes_min_count
  agents_nodes_max_count = var.agents_nodes_max_count

  # Monitoring
  platform_namespace      = var.platform_namespace
  argo_namespace          = var.argo_namespace
  github_broker_namespace = var.github_broker_namespace
  agents_namespace        = var.agents_namespace

  # From networking
  aks_nodes_subnet_id = module.networking.subnets.aks_nodes.id
  egress_ip_id        = module.networking.public_ips.egress.id

  # From shared
  log_analytics_workspace_id = module.shared.log_analytics.id

  # Persistent principals survive cluster rebuilds.
  control_plane_identity = module.identities.control_plane
  kubelet_identity       = module.identities.kubelet
  workload_identity_ids  = { for k, mi in module.identities.workloads : k => mi.id }

  workload_identities = local.workload_identities
}

# ============
#  Kubernetes
# ============

module "kubernetes" {
  source = "./modules/kubernetes"

  workload_identities = local.workload_identities
  workload_client_ids = { for k, mi in module.identities.workloads : k => mi.client_id }
  agent_roles         = var.agent_roles

  platform_namespace      = var.platform_namespace
  argo_namespace          = var.argo_namespace
  github_broker_namespace = var.github_broker_namespace
  agents_namespace        = var.agents_namespace
  azure_imds_endpoint     = var.azure_imds_endpoint

  # Provider config depends on the cluster, which is not a dependency Terraform sees.
  depends_on = [module.cluster]
}

# =====================
#  Workload Identities
# =====================
# Platform services only. Agent pods get no cloud identity (ADR-003).
# Each key becomes one managed identity with one federated credential per service account.
# Service accounts are created by the kubernetes module; Helm charts reference them by name.
# `namespace` also sets the federated credential subject (cluster module).

locals {
  workload_identities = {
    workflow-service = {
      namespace        = var.platform_namespace
      service_accounts = ["workflow-service"]
    }
    artifact-service = {
      namespace        = var.platform_namespace
      service_accounts = ["artifact-service"]
    }
    token-broker = {
      namespace        = var.github_broker_namespace
      service_accounts = ["token-broker"]
    }
    # Both read the workflow archive in Postgres
    argo-workflow-controller = {
      namespace        = var.argo_namespace
      service_accounts = ["argo-workflow-controller"]
    }
    argo-server = {
      namespace        = var.argo_namespace
      service_accounts = ["argo-server"]
    }
  }
}
