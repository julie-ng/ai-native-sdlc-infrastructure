# AI-native SDLC — Infrastructure

Terraform for the AI SDLC platform on Azure: one AKS cluster plus the backing services it needs. Single environment (dev).

> [!IMPORTANT]
> First pass written without Azure access. Passes `terraform validate` and `tflint`; **never planned or applied**. See [Unverified](#unverified).

## Modules

Apply one at a time, in this order. Each depends on the outputs of the ones before it.

| # | Module | Resource group | Creates |
|---|---|---|---|
| 1 | [`networking`](./modules/networking/) | `ai-sdlc-networking-rg` | VNet, `aks-nodes-subnet` (service endpoints: Key Vault, Storage), empty `AzureFirewallSubnet`, ingress + egress static IPs |
| 2 | [`shared`](./modules/shared/) | `ai-sdlc-shared-rg` | PostgreSQL Flexible Server (`workflow`, `argo` DBs), Blob Storage: `ai-sdlc{suffix}artifacts` (artifact service), `ai-sdlc{suffix}argo` (Argo artifact repository), Key Vault, ACR (pull only), Log Analytics (North Europe) |
| 3 | [`identities`](./modules/identities/) | `ai-sdlc-identities-rg` | Persistent control-plane, kubelet and platform workload identities; role assignments for networking, ACR, Storage and Key Vault |
| 4 | [`cluster`](./modules/cluster/) | `ai-sdlc-cluster-rg` | AKS (`system`, `platform` and `agents` pools, Key Vault CSI driver), cluster-specific workload federation, Container Insights, cluster-admin role assignment |
| 5 | [`kubernetes`](./modules/kubernetes/) | — | Namespaces `platform`, `argo`, `github-broker`, `agents`; ServiceAccounts; `argo-executor` ServiceAccount + Role; monitor agent ConfigMap |

Resource group names carry no random suffix. AKS creates its Azure-managed node resources in `ai-sdlc-aks-managed-rg`. Globally unique names (Key Vault, Storage, ACR, Postgres) and the cluster carry a random 4-character suffix, kept in state.

## Prerequisites

- `terraform` ≥ 1.10, `az`, `kubelogin`, `kubectl`, `jq`
- `private.auto.tfvars` (git-ignored) with your IP for the Key Vault, Storage and Postgres firewalls:

```hcl
admin_ip_ranges = ["x.x.x.x/32"]
```

> [!IMPORTANT]
> CIDR notation is required. For a single IPv4 address, append `/32`.

### Log in to Azure 

Terraform authenticates via the ambient Azure CLI session, not a stored credential:

```sh
az login
az account set --subscription <subscription-id>
```

**There are no hard-coded user, tenant or subscription IDs anywhere in this repository.** Every place that needs to know who's applying reads from references, e.g. `data.azurerm_client_config.current` or `data.azuread_user`.

> [!NOTE]
> Must be a user sign-in, not a service principal — the Postgres admin lookup and `principal_type = "User"` assume one.

## Deploy

```bash
make init
make plan-networking && make apply
make plan-shared     && make apply
make plan-identities && make apply
make plan-cluster    && make apply
make kubecontext
make plan-kubernetes && make apply
make plan            # expect: no changes
```

`-target` is used for staging only. The final untargeted `plan` confirms nothing was missed.

Managed identity names have no random suffix. Identities and their role assignments on shared resources survive cluster rebuilds. Cluster recreation updates workload federation to its OIDC issuer. Identity resources and their group have `prevent_destroy` guards.

> [!IMPORTANT]
> Before applying this module split, discard any earlier saved plan and generate a fresh one. `moved.tf` preserves Terraform addresses, but existing identities in the cluster resource group would still require replacement to use the new group; `prevent_destroy` blocks that replacement. If identities have already been deployed, review a separate migration before applying.

> [!NOTE]
> **Regions**: Defaults to `westeurope`; see [`defaults.auto.tfvars`](./defaults.auto.tfvars). PostgreSQL is pinned to `northeurope` because this subscription cannot provision it in West Europe. Log Analytics and the Container Insights data collection rule are also pinned to `northeurope` and must share a region.

### Start and stop the cluster

After a successful deployment, with the local Terraform state available and Azure CLI signed into the deployment subscription:

```sh
make stop-cluster
make start-cluster
```

These run `az aks stop` / `az aks start` using the resource group and cluster name from `terraform output -json summary`. They wait for Azure to complete the operation. Missing outputs stop the command before Azure is called. Backing services such as PostgreSQL remain running and bill separately.

[AKS stop/start considerations](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster): stopping releases capacity, so restart is subject to availability. After stopping, Microsoft advises waiting 15–30 minutes before starting again. Standalone pods are deleted during stop; controller-managed workloads are restored on start.

### Node pools

| Pool | VM size | Minimum nodes | Maximum nodes |
|---|---|---:|---:|
| `system` | `Standard_D2s_v5` | 1 | 2 |
| `platform` | `Standard_D2s_v5` | 1 | 2 |
| `agents` | `Standard_D4s_v5` | 1 | 2 |

The human developer retains one D2s v5 system node for the POC; Azure acceptance remains unverified until apply.

All pools autoscale within these bounds. For the POC, use [AKS cluster start/stop](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster) when idle. Stopping releases capacity, so restarting remains subject to regional availability. User-pool scale-to-zero is a [deferred target design (#3)](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/3); no application wake-up infrastructure is included.

Workload manifests must select `kubernetes.azure.com/agentpool: platform` for platform services or `kubernetes.azure.com/agentpool: agents` for agent pods. Agent pods must also tolerate `workload=agents:NoSchedule`. These scheduling settings do not provide a security isolation boundary. Workload templates are maintained outside this repo.

### Monitoring costs

| Control | POC setting |
|---|---|
| Workspace retention | 30 days; no extended retention configured |
| Daily ingestion cap | 0.1 GB/day (about 100 MB), workspace-wide |
| Collected tables | `ContainerLogV2`, `KubeEvents`, `KubePodInventory` |
| Pod inventory | Every 5 minutes, for `platform`, `argo`, `github-broker`, `agents` |
| Kubernetes events | Non-Normal events in those four namespaces; event-driven |
| Container logs | stdout and stderr; exclude `kube-system`, `gatekeeper-system`, `azure-arc`, `kube-public`, `kube-node-lease`, `calico-system`, `default` at the agent |

The [logs/events preset](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable#configuration-options) keeps troubleshooting data without ingesting `Perf`, `InsightsMetrics`, or the extra inventory tables. Inventory is sampled more slowly; this does not throttle container logs or events. Historical CPU/memory charts and full Container Insights visualizations are not provided by this configuration. No Managed Prometheus, Grafana, syslog, or AKS audit/control-plane log export is enabled by this repo.

[Retention below 31 days does not reduce Analytics ingestion charges](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/data-retention-configure). The [daily cap](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/daily-cap) is a backstop, not a hard spending limit: overshoot is billable, and collection stops until the workspace reset. 0.1 GB/day is an initial POC choice, not a measured workload requirement. Logs lost during a cap-related collection gap are not guaranteed to be recoverable.

Apply the workspace cap with `make plan-shared` / `make apply` before the cluster stage. Apply `module.kubernetes` immediately after the cluster stage and before deploying workloads: it installs the [monitor agent ConfigMap](https://github.com/microsoft/Docker-Provider/blob/ci_prod/kubernetes/container-azm-ms-agentconfig.yaml). Until then, agent defaults apply. The DCR namespace filter covers events/inventory; the ConfigMap separately excludes container logs before upload. Container log filtering is an exclusion list, so review it when adding namespaces. App and agent log verbosity still determines volume; avoid debug output and request-body logging by default.

### Kubernetes Namespaces

Namespaces form part of the security boundary, enforced through ServiceAccounts, RBAC and Azure Workload Identity. The GitHub broker has its own namespace to isolate its ServiceAccount and Key Vault secret mounts, including the GitHub App private key.

| Namespace | What goes here |
|---|---|
| `platform` | Workflow service and artifact service, with their workload-identity ServiceAccounts. |
| `argo` | Argo Workflows controller and server, with their workload-identity ServiceAccounts. |
| `github-broker` | GitHub token broker, with its workload-identity ServiceAccount (`token-broker`). |
| `agents` | Agent workflow pods; ServiceAccounts for `planner`, `coder`, `reviewer` and `open-pr`; `argo-executor` ServiceAccount and RBAC. Agent ServiceAccounts have no cloud identity. |

### After apply — manual steps

Kept out of Terraform so secrets never land in state, or because no azurerm resource covers it.

- **Argo executor token Secret.** Argo mounts it into the executor containers of agent pods. Legacy non-expiring token — kept out of Terraform state:

  ```sh
  kubectl apply -f - <<YAML
  apiVersion: v1
  kind: Secret
  type: kubernetes.io/service-account-token
  metadata:
    name: argo-executor.service-account-token
    namespace: agents
    annotations:
      kubernetes.io/service-account.name: argo-executor
  YAML
  ```

- **Postgres roles for workload identities.** `workflow-service`, `argo-workflow-controller` and `argo-server` connect via Entra ID, but need database roles. As the Entra admin, create a role per managed identity (`pgaadauth_create_principal`) and grant it its database. **Unverified:** exact function arguments for managed identities.
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
| Key Vault, both storage accounts | Public endpoint, default deny. Allowed: AKS subnet via service endpoint, `admin_ip_ranges`. |
| PostgreSQL | Public endpoint, firewall: cluster egress IP, `admin_ip_ranges`. Flexible Server has no service endpoint support — traffic is not on the Azure backbone. |
| ACR | Public endpoint. Basic SKU has no network rules. Kubelet pulls; nothing in this repo or GitHub can push — images are pushed manually. |

Egress: all cluster outbound traffic leaves via `ai-sdlc-egress-ip` (load balancer outbound IP). No egress filtering.

## Unverified

Written blind. Check on first apply:

- `make start-cluster` / `make stop-cluster` resolve the saved outputs and complete successfully against Azure; only command construction and failure handling were checked offline.
- `-target=module.networking` / `module.shared` plans succeed even though the `kubernetes` provider is configured from cluster outputs that don't exist yet.
- `kube_config[0].host` and `cluster_ca_certificate` are populated with local accounts disabled.
- `azurerm_storage_container.id` is the ARM resource ID, usable as a role assignment scope.
- `os_sku = "AzureLinux"`, `postgres_version = "17"`, VM sizes available in the chosen region.
- Successful creation of PostgreSQL 17 with `B_Standard_B1ms` in `northeurope`. The human developer confirmed regional capabilities are available; server creation is still unverified.
- The identities module creates role assignments before AKS creation, and a cluster rebuild preserves principal IDs and role assignments on shared resources while updating federation.
- The DCR collects only the three selected tables; the agent applies namespace/event filters after `module.kubernetes` is applied; the workspace cap and actual ingestion volume behave as documented.
- All three node pools provision with their configured sizes; workload templates select the intended pools and tolerate the agent taint.
- AKS accepts the custom node resource group name `ai-sdlc-aks-managed-rg` on creation.
- Network Contributor on the egress IP is sufficient for the control plane to attach it.

## Docs

- [Decisions](./docs/decisions.md) — decision log for this repo
- [Inventory](./docs/inventory.md) — resource groups and conventions from the earlier cloudkube repos this is based on
