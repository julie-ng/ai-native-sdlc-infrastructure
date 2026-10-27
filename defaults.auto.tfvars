name     = "ai-sdlc"
location = "westeurope" # PostgreSQL and monitoring are pinned to northeurope; see docs/decisions.md.

default_tags = {
  env  = "dev"
  iac  = "terraform"
  demo = "true"
}

# Set in git-ignored `private.auto.tfvars`, see README:
#   admin_ip_ranges = ["x.x.x.x/32"]

# ============
#  Networking
# ============

vnet_address_space         = ["10.0.0.0/16"]
aks_nodes_address_prefixes = ["10.0.0.0/22"]
firewall_address_prefixes  = ["10.0.8.0/26"] # Azure Firewall needs at least /26

# Outside the VNet - CNI Overlay
pod_cidr       = "10.244.0.0/16"
service_cidr   = "172.16.0.0/16"
dns_service_ip = "172.16.0.10"

# =====
#  AKS
# =====
# POC: keep one node per pool; use cluster start/stop when idle.

# Human-selected POC sizing; provisioning confirmed on 2026-10-22.
system_vm_size         = "Standard_D2s_v5"
system_nodes_min_count = 1
system_nodes_max_count = 2

platform_vm_size         = "Standard_D2s_v5"
platform_nodes_min_count = 1
platform_nodes_max_count = 2

agents_vm_size         = "Standard_D4s_v5"
agents_nodes_min_count = 1
agents_nodes_max_count = 2

agent_roles = ["planner", "coder", "reviewer", "open-pr"]

# ============
#  Kubernetes
# ============

platform_namespace      = "platform"
argo_namespace          = "argo"
github_broker_namespace = "github-broker"
agents_namespace        = "agents" # untrusted: Pod Security baseline + IMDS blocked

# ================
#  Azure Platform
# ================
# Owned by Azure, not this repo - do not change.
# https://learn.microsoft.com/en-us/azure/virtual-machines/instance-metadata-service

azure_imds_endpoint = "169.254.169.254"

# ==========
#  Postgres
# ==========

postgres_version   = "17"
postgres_sku_name  = "B_Standard_B1ms" # Burstable
postgres_databases = ["workflow", "argo"]

# =================
#  Platform Stop
# =================

platform_stop = {
  identity_name = "platform-stop-mi"
  issuer        = "https://token.actions.githubusercontent.com"
  audience      = "api://AzureADTokenExchange"
  subject       = "repo:julie-ng/ai-native-sdlc-infrastructure:ref:refs/heads/main"
  aks_role      = "Azure Kubernetes Service Contributor Role"
  postgres_role = "Contributor"
}
