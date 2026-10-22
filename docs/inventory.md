# Inventory — cloudkube repos

Reference for this repo's design. Taken from the public repos on 2026-10-22; describes their code, not what is deployed.

- [cloudkube-networking-iac](https://github.com/julie-ng/cloudkube-networking-iac)
- [cloudkube-aks-clusters](https://github.com/julie-ng/cloudkube-aks-clusters)
- [cloudkube-shared-infra](https://github.com/julie-ng/cloudkube-shared-infra)

## Resource groups

| Repo | Resource group | Resources |
|---|---|---|
| networking | `cloudkube-{env}-networking-rg` | VNet `cloudkube-{env}-vnet` (`10.0.0.0/16`, reserved K8s service range stored in tags); subnets `aks-nodes-subnet` (`/22`), `aks-api-server-subnet` (`/24`); static IP `cloudkube-{env}-aks-ingress-ip` (`prevent_destroy`) |
| aks-clusters | `cloudkube-{env}-{suffix}-rg` | AKS `…-cluster`; identities `…-control-plane-mi`, `…-kubelet-mi`, `…-ingress-mi`; Key Vault `…-kv`; per workload: identity `{app}-{suffix}-workload-mi`, federated credential `{app}-workload`, namespace `{app}`, ServiceAccount `{app}-workload` |
| aks-clusters | `cloudkube-{env}-{suffix}-managed-rg` | AKS node resource group (replaces `MC_…`) |
| shared-infra | `cloudkube-shared-rg` | ACR `cloudkubecr`; DNS zone `cloudkube.io`; Key Vaults `cloudkube-{env}-kv` (TLS certs); Storage `cloudkubestorage`; Log Analytics `cloudkube-log-analytics` (read by aks-clusters, created outside these repos) |
| shared-infra | — (Entra ID) | App + service principal `{repo}-github-actions-{env}`, federated credential `{repo}-{env}-github-deploy` |

Terraform state storage accounts are not managed in any of the three.

## Naming conventions

- `{base}-{env}[-{suffix}]-{type}`, lowercase, hyphenated. Types: `-rg`, `-vnet`, `-cluster`, `-mi`, `-kv`, `-ip`, `-subnet`.
- Random suffix (3–4 chars) only on short-lived resources (cluster group). Networking and shared resources unsuffixed.
- No-dash resources squashed: `cloudkubecr`, `cloudkubestorage`.
- Tags: `env`, `iac = terraform`, `demo = true`, `public = true`.

## Terraform style

- Split by lifecycle: networking → shared → cluster, separate state each, linked by naming convention + `data` lookups.
- Module files by concern: `_aks.tf`, `_identities.tf`, `_rbac.tf`; `# ====` banner comments.
- One `summary` output object, read by a Makefile via `jq`.
- `defaults.auto.tfvars` + `environments/{env}/*.tfvars`.
- Backend: partial config via `-backend-config`, `use_azuread_auth`, one storage account per environment.
- Add-ons (Helm, `kubectl`) via Makefile, not Terraform.
