name     = "aisdlc"
location = "northeurope" # placeholder until region capacity is checked

default_tags = {
  env  = "dev"
  iac  = "terraform"
  demo = "true"
}

# Set in git-ignored `private.auto.tfvars`, see README:
#   admin_principal_name = "…"
#   admin_ip_ranges      = ["x.x.x.x/32"]

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
# Target design has three pools: system, platform, agents.
# For now agents run on the platform pool.

system_vm_size         = "Standard_D2s_v5"
system_nodes_min_count = 1
system_nodes_max_count = 2

platform_vm_size         = "Standard_D4s_v5"
platform_nodes_min_count = 1
platform_nodes_max_count = 3

agent_roles = ["planner", "coder", "reviewer", "open-pr"]

# ==========
#  Postgres
# ==========

postgres_version   = "17"
postgres_sku_name  = "B_Standard_B1ms" # Burstable
postgres_databases = ["workflow", "argo"]
