# AI-native SDLC — Infrastructure

Terraform for the AISDLC platform on Azure: one AKS cluster plus the backing services it needs. Single environment (dev).

> [!IMPORTANT]
> First pass written without Azure access. Passes `terraform validate` and `tflint`; **never planned or applied**. See [Unverified](#unverified).

## Modules

Apply one at a time, in this order. Each depends on the outputs of the ones before it.

| # | Module | Resource group | Creates |
|---|---|---|---|
| 1 | [`networking`](./modules/networking/) | `aisdlc-networking-rg` | VNet, `aks-nodes-subnet` (service endpoints: Key Vault, Storage), empty `AzureFirewallSubnet`, ingress + egress static IPs |
| 2 | [`shared`](./modules/shared/) | `aisdlc-shared-rg` | PostgreSQL Flexible Server (`workflow`, `argo` DBs), Blob Storage (`artifacts`), Key Vault, ACR, Log Analytics |
| 3 | [`cluster`](./modules/cluster/) | `aisdlc-{suffix}-rg` | AKS (`system` + `platform` pools), control-plane + kubelet identities, workload identities, Container Insights, role assignments |
| 4 | [`kubernetes`](./modules/kubernetes/) | — | Namespaces `platform`, `argo`, `github-broker`, `agents`; ServiceAccounts |

Networking and shared groups carry no suffix — longer lifecycle than the cluster. Globally unique names (Key Vault, Storage, ACR, Postgres) and the cluster carry a random 4-character suffix, kept in state.

## Prerequisites

- `terraform` ≥ 1.10, `az`, `kubelogin`, `kubectl`, `jq`
- `private.auto.tfvars` (git-ignored) with your IP for the Key Vault, Storage and Postgres firewalls:

```hcl
admin_ip_ranges = ["x.x.x.x/32"]
```

### Azure authentication

Terraform authenticates via the ambient Azure CLI session, not a stored credential:

```sh
az login
az account set --subscription <subscription-id>
```

**There are no hard-coded user, tenant or subscription IDs anywhere in this repository.** Every place that needs to know who's applying — the Postgres Entra admin, the deployer's Key Vault grants, the AKS cluster-admin role assignment — reads it from `data.azurerm_client_config.current`, which resolves to whoever `az login` signed in as. The Postgres admin's UPN is looked up from that object ID via `data.azuread_user`. `subscription_id` is only a *required* provider property when `use_cli` is `false`; with CLI authentication the provider takes whatever subscription `az account set` selected. Log in as the wrong account and Terraform still builds correctly — just for the wrong person.

Must be a user sign-in, not a service principal — the Postgres admin lookup and `principal_type = "User"` assume one.

Region: `location` in [`defaults.auto.tfvars`](./defaults.auto.tfvars). `northeurope` is a placeholder.

## Deploy

```bash
make init
make plan-networking && make apply
make plan-shared     && make apply
make plan-cluster    && make apply
make kubecontext
make plan-kubernetes && make apply
make plan            # expect: no changes
```

`-target` is used for staging only. The final untargeted `plan` confirms nothing was missed.

### After apply — manual steps

Kept out of Terraform so secrets never land in state, or because no azurerm resource covers it.

- **Postgres roles for workload identities.** `workflow-service` and `argo` connect via Entra ID, but need database roles. As the Entra admin, create a role per managed identity (`pgaadauth_create_principal`) and grant it its database. **Unverified:** exact function arguments for managed identities.
- **Key Vault secrets.** GitHub App private key for the token broker ([ADR-012](https://github.com/julie-ng/autonomous-agents-setup/blob/main/architecture/decisions/012-cloud-agent-identity.md)).

## Network

| Range | Use |
|---|---|
| `10.0.0.0/16` | VNet |
| `10.0.0.0/22` | `aks-nodes-subnet` — nodes only |
| `10.0.8.0/26` | `AzureFirewallSubnet` — reserved, no firewall |
| `10.244.0.0/16` | Pods (CNI Overlay, outside VNet) |
| `172.16.0.0/16` | Kubernetes services; DNS `172.16.0.10` |

| Service | Access |
|---|---|
| Key Vault, Storage | Public endpoint, default deny. Allowed: AKS subnet via service endpoint, `admin_ip_ranges`. |
| PostgreSQL | Public endpoint, firewall: cluster egress IP, `admin_ip_ranges`. Flexible Server has no service endpoint support — traffic is not on the Azure backbone. |
| ACR | Public endpoint. Basic SKU has no network rules. |

Egress: all cluster outbound traffic leaves via `aisdlc-egress-ip` (load balancer outbound IP). No egress filtering.

## Unverified

Written blind. Check on first apply:

- `-target=module.networking` / `module.shared` plans succeed even though the `kubernetes` provider is configured from cluster outputs that don't exist yet.
- `kube_config[0].host` and `cluster_ca_certificate` are populated with local accounts disabled.
- `azurerm_storage_container.id` is the ARM resource ID, usable as a role assignment scope.
- `os_sku = "AzureLinux"`, `postgres_version = "17"`, VM sizes available in the chosen region.
- Network Contributor on the egress IP is sufficient for the control plane to attach it.

## Docs

- [Decisions](./docs/decisions.md) — decision log for this repo
- [Inventory](./docs/inventory.md) — resource groups and conventions from the earlier cloudkube repos this is based on
