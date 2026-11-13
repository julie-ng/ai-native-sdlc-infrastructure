# AI-native SDLC — Infrastructure

Terraform for the AI SDLC platform on Azure: one AKS cluster plus the backing services it needs. Single environment (dev).

> [!IMPORTANT]
> All infrastructure modules were deployed successfully by the human developer on 2026-10-22. Argo hello-world succeeded on 2026-11-05; platform services and agent workflows have not been tested. Agents verify offline only; see [Unverified](#unverified).

## Docs

- [Deployment](./docs/deployment.md) — prerequisites, apply order, start/stop, Argo install, manual steps
- [Decisions](./docs/decisions-log.md) — decision log for this repo
- [Workload integration](./docs/workload-integration.md) — ServiceAccounts, labels and secret mounts that workloads in other repos must use
- [Monitoring costs](./docs/monitoring.md) — Container Insights collection and cost controls
- [Verification log](./docs/verification-log.md) — checks completed by the human developer
- [Inventory](./docs/inventory.md) — resource groups and conventions from the earlier cloudkube repos this is based on

## What gets deployed

### Modules

Applied one at a time, in this order. Each depends on the outputs of the ones before it.

| # | Module | Resource group | Creates |
|---|---|---|---|
| 1 | [`networking`](./modules/networking/) | `ai-sdlc-networking-rg` | VNet, subnets, static IPs |
| 2 | [`shared`](./modules/shared/) | `ai-sdlc-shared-rg` | PostgreSQL, Blob Storage, Key Vault, ACR, Log Analytics, local-dev service principal |
| 3 | [`identities`](./modules/identities/) | `ai-sdlc-identities-rg` | Managed identities that outlive the cluster, and their role assignments |
| 4 | [`cluster`](./modules/cluster/) | `ai-sdlc-cluster-rg` | AKS, workload identity federation, Container Insights, cluster-admin role assignment |
| 5 | [`kubernetes`](./modules/kubernetes/) | — | Namespaces, ServiceAccounts, RBAC, NetworkPolicy, SecretProviderClasses, monitor agent ConfigMap |
| 6 | [`platform_stop_mi`](./modules/platform_stop_mi/) | `ai-sdlc-identities-rg` (existing) | GitHub OIDC identity that stops AKS and PostgreSQL |

Resource group names carry no random suffix. AKS creates its own node resources in `ai-sdlc-aks-managed-rg`. Globally unique names and the cluster carry a random 4-character `{suffix}`, kept in state.

### Azure resources

| Resource | Name | Module | Configuration |
|---|---|---|---|
| Virtual network | `ai-sdlc-vnet` | networking | `10.0.0.0/16` |
| Subnet | `aks-nodes-subnet` | networking | `10.0.0.0/22`, nodes only; service endpoints for Key Vault and Storage |
| Subnet | `AzureFirewallSubnet` | networking | `10.0.8.0/26`, reserved; no firewall deployed |
| Public IP | `ai-sdlc-egress-ip` | networking | Cluster outbound (load balancer) |
| Public IP | `ai-sdlc-ingress-ip` | networking | Reserved, unused |
| PostgreSQL Flexible Server | `ai-sdlc-{suffix}-psql` | shared | v17, Burstable B1ms, North Europe, Entra-only auth; databases `workflow`, `argo` |
| Storage account | `aisdlc{suffix}artifacts` | shared | Containers `artifacts`, `local-dev`; shared keys off |
| Storage account | `aisdlc{suffix}argo` | shared | Container `argo` (Argo artifact repository); shared keys off |
| Key Vault | `ai-sdlc-{suffix}-kv` | shared | RBAC mode; secret values added manually, never in Terraform |
| Container registry | `aisdlc{suffix}cr` | shared | Basic SKU, admin user off |
| Log Analytics workspace | `ai-sdlc-log-analytics` | shared | North Europe, 30-day retention, 0.1 GB/day cap; see [monitoring costs](./docs/monitoring.md) |
| Entra app + service principal | `ai-sdlc-local-dev` | shared | Runs the artifact service from a laptop; credential created manually |
| AKS cluster | `ai-sdlc-{suffix}-cluster` | cluster | Free tier; Entra ID + Azure RBAC, local accounts off; OIDC issuer and workload identity; Azure CNI Overlay with Cilium; Key Vault CSI add-on |
| Data collection rule | `MSCI-northeurope-{cluster}` | cluster | Container Insights: `ContainerLogV2`, `KubeEvents`, `KubePodInventory` |
| Managed identities | 12, see [Identity and access model](#identity-and-access-model-iam) | identities, platform_stop_mi | User-assigned, `prevent_destroy` |
| Role assignments | see [Identity and access model](#identity-and-access-model-iam) | shared, identities, cluster, platform_stop_mi | Scoped to the narrowest resource |

### Network access

| Range | Use |
|---|---|
| `10.0.0.0/16` | VNet |
| `10.0.0.0/22` | `aks-nodes-subnet` — nodes only |
| `10.0.8.0/26` | `AzureFirewallSubnet` — reserved, no firewall |
| `10.244.0.0/16` | Pods (CNI Overlay with Cilium, outside VNet) |
| `172.16.0.0/16` | Kubernetes services; DNS `172.16.0.10` |

| Service | Access |
|---|---|
| Key Vault, both storage accounts | Public endpoint, default deny. Allow AKS subnet via service endpoint and `admin_ip_ranges`; trusted Azure service bypass is also enabled. Authentication and role assignments still apply. |
| PostgreSQL | Public endpoint, firewall: cluster egress IP, `admin_ip_ranges`. Flexible Server has no service endpoint support. Public endpoint does not imply public-internet routing between Azure services; see [Microsoft global network](https://learn.microsoft.com/en-us/azure/networking/microsoft-global-network). |
| ACR | Public endpoint. Basic SKU has no network rules. Kubelet pulls; only the two GitHub push identities can push. |

Egress: all cluster outbound traffic leaves via `ai-sdlc-egress-ip`. No egress filtering, except IMDS for `agents`.

### Node pools

| Pool | VM size | Minimum nodes | Maximum nodes |
|---|---|---:|---:|
| `system` | `Standard_D2s_v5` | 1 | 2 |
| `platform` | `Standard_D2s_v5` | 1 | 2 |
| `agents` | `Standard_D4s_v5` | 1 | 2 |

POC sizing, not a production recommendation. All pools autoscale within these bounds; use start/stop when idle. User-pool scale-to-zero is a [deferred target design (#3)](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/3). Scheduling labels and taints for workloads: see [workload integration](./docs/workload-integration.md#scheduling).

### Kubernetes resources

| Namespace | Runs | Terraform creates |
|---|---|---|
| `platform` | Platform-services app (workflow and artifact APIs) | ServiceAccount `platform-services`; SecretProviderClass `platform-services-secrets` |
| `argo` | Argo Workflows controller and server | ServiceAccounts `argo-workflow-controller`, `argo-server`; controller config Role |
| `github-broker` | GitHub token broker | ServiceAccount `token-broker` |
| `agents` | Agent workflow pods and the trusted `foreman` step | ServiceAccounts `planner`, `coder`, `reviewer`, `open-pr`, `foreman`, `argo-executor`; Roles for the Argo controller, executor and foreman; SecretProviderClasses `coder-secrets`, `planner-secrets`, `foreman-admin-token`; NetworkPolicy `deny-imds` |
| `kube-system` | — | ConfigMap `container-azm-ms-agentconfig` (container log filters) |

Agent pods run LLM-driven code, so `agents` has two extra controls:

- **Pod Security `baseline`, enforced.** Rejects `hostNetwork`, `privileged`, `hostPath`, host ports and capabilities beyond the container runtime defaults, so no Docker-in-Docker. `restricted` is warn/audit only: `kubectl apply` prints what templates would need for it.
- **NetworkPolicy `deny-imds`.** Allows all egress except `169.254.169.254`, so pods can't get tokens for node identities such as the kubelet's. Only IMDS is blocked: agents still reach every pod and the internet. Workload identity doesn't need IMDS: it uses the projected ServiceAccount token.

Argo itself is installed with Helm, not Terraform; see [deployment](./docs/deployment.md#install-argo-workflows).

## Identity and access model (IAM)

Workload identities only. The other identities are summarised [below](#other-identities). How workloads mount their secrets: [workload integration](./docs/workload-integration.md).

### Who can become which identity?

Each Kubernetes ServiceAccount is trusted by exactly one managed identity through a federated identity credential (FIC). FIC subject = `system:serviceaccount:<ns>:<sa>`, issuer = the AKS OIDC issuer.

```
  KUBERNETES (ai-sdlc-cluster-rg)                     ENTRA ID (ai-sdlc-identities-rg)
  namespace / ServiceAccount                          user-assigned managed identity
  ─────────────────────────────────────────           ───────────────────────────────

  ┌─ platform ─────────────────────────────┐
  │  platform-services                     │ ══FIC══► platform-services-mi
  └────────────────────────────────────────┘
  ┌─ github-broker ────────────────────────┐
  │  token-broker                          │ ══FIC══► gh-token-broker-mi
  └────────────────────────────────────────┘
  ┌─ argo ─────────────────────────────────┐
  │  argo-workflow-controller              │ ══FIC══► argo-workflow-controller-mi
  │  argo-server                           │ ══FIC══► argo-server-mi
  └────────────────────────────────────────┘
  ┌─ agents  (untrusted: PSS baseline, IMDS blocked) ┐
  │  foreman      (trusted bootstrap step) │ ══FIC══► foreman-mi
  │  planner                               │ ══FIC══► planner-mi       ┐ #26 exception:
  │  coder                                 │ ══FIC══► coder-mi         ┘ secret reads only
  │  reviewer                              │ ── no identity
  │  open-pr                               │ ── no identity
  │  argo-executor                         │ ── no identity (ADR-003)
  └──────────────────────────────────────────────────┘
```

### Where does each grant land?

Grants are pinned to the level of the resource hierarchy they are scoped to. Nothing is granted at vault scope; storage grants are at container scope except the delegator role.

```
Legend   ◄── role ──   Azure RBAC role assignment (Terraform, modules/identities/_rbac.tf)
         ◄┄┄ SQL ┄┄┄   PostgreSQL role + GRANTs (manual, docs/deployment.md; not Azure RBAC)
         ·· none       resource exists, no workload identity can read it


KEY VAULT  ai-sdlc-{suffix}-kv                      ·· no workload grant at vault scope
│                                                     (only the deployer: Key Vault Administrator)
│
├─ secret  platform-services-admin-token  ◄── Secrets User ── platform-services-mi
│                                         ◄── Secrets User ── foreman-mi
├─ secret  platform-services-hmac-key     ◄── Secrets User ── platform-services-mi
├─ secret  token-broker-gh-app-private-key◄── Secrets User ── gh-token-broker-mi
├─ secret  agent-gpg-private-key          ◄── Secrets User ── coder-mi
├─ secret  julieio-goose-github-pat       ◄── Secrets User ── coder-mi, planner-mi
├─ secret  vercel-ai-gateway-api-key      ◄── Secrets User ── coder-mi, planner-mi
├─ secret  agent-gpg-public-key           ·· none
├─ secret  agent-gpg-fingerprint          ·· none
└─ secret  argo-executor-token            ·· none  (copied into a K8s Secret by hand)


STORAGE ACCOUNT  aisdlc{suffix}artifacts            ◄── Blob Delegator ── platform-services-mi
│                                                     (signs user-delegation SAS; no blob
│                                                      access on its own)
├─ container  artifacts                   ◄── Blob Data Contributor ── platform-services-mi
└─ container  local-dev                   (local dev service principal only, not a workload)


STORAGE ACCOUNT  aisdlc{suffix}argo                 ·· no workload grant at account scope
│
└─ container  argo                        ◄── Blob Data Contributor ── argo-workflow-controller-mi
                                          ◄── Blob Data Reader ─────── argo-server-mi


POSTGRESQL  ai-sdlc-{suffix}-psql                   Entra-only auth; Entra admin = deployer
│                                                     (Azure RBAC grants no data access here)
│
├─ database  workflow                     ◄┄┄ SQL ┄┄┄ platform-services-mi
│     DB: CONNECT, CREATE   schema public: USAGE, CREATE   (applied 2026-11-10, #31)
│
└─ database  argo                         ◄┄┄ SQL ┄┄┄ argo-workflow-controller-mi   (not yet granted, #33)
                                          ◄┄┄ SQL ┄┄┄ argo-server-mi               (not yet granted, #33)
```

### Access matrix

One table per service. Rows are the narrowest scope a grant can land on; columns are the identities with any grant on that service. Empty = no access.

**Key Vault** — `Key Vault Secrets User`, one assignment per secret

| Secret | `platform-services` | `foreman` | `gh-token-broker` | `planner` | `coder` |
|---|:---:|:---:|:---:|:---:|:---:|
| `platform-services-admin-token` | Read | Read | | | |
| `platform-services-hmac-key` | Read | | | | |
| `token-broker-gh-app-private-key` | | | Read | | |
| `agent-gpg-private-key` | | | | | Read |
| `julieio-goose-github-pat` | | | | Read | Read |
| `vercel-ai-gateway-api-key` | | | | Read | Read |
| `agent-gpg-public-key` | | | | | |
| `agent-gpg-fingerprint` | | | | | |
| `argo-executor-token` | | | | | |

**Blob Storage**

| Scope | `platform-services` | `argo-workflow-controller` | `argo-server` |
|---|:---:|:---:|:---:|
| `aisdlc{suffix}artifacts` account | Delegator¹ | | |
| └ `artifacts` container | Read/write | | |
| └ `local-dev` container | | | |
| `aisdlc{suffix}argo` account | | | |
| └ `argo` container | | Read/write | Read |

- Read/write = `Storage Blob Data Contributor`; Read = `Storage Blob Data Reader`.
- ¹ `Storage Blob Delegator`: signs user-delegation SAS URLs. Grants no blob access by itself; a SAS can't exceed the container-scoped grant.
- `local-dev` is used only by the local-dev service principal, not a workload identity.

**PostgreSQL** — database roles granted with SQL, not Azure RBAC

| Database | `platform-services` | `argo-workflow-controller` | `argo-server` |
|---|:---:|:---:|:---:|
| `workflow` | Read/write² | | |
| `argo` | | Not yet granted ([#33](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/33)) | Not yet granted ([#33](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/33)) |

- ² `CONNECT, CREATE` on the database and `USAGE, CREATE` on schema `public`; the app owns the tables it creates. Applied 2026-11-10 ([#31](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/31)).

**Kubernetes API — broker ServiceAccount**

| ServiceAccount | Scope | Permission |
|---|---|---|
| `github-broker/token-broker` | Cluster | `authentication.k8s.io/tokenreviews: create` |
| `github-broker/token-broker` | `agents` namespace | `pods: get` |

The broker's `github-broker-secrets` SecretProviderClass mounts only `token-broker-gh-app-private-key`, using its existing secret-scoped Key Vault grant. No secret values or Kubernetes Secret synchronization are managed by Terraform.

### Network reach

Applies to every pod, not per identity:

```
  any pod on AKS nodes ──service endpoint──► Key Vault, both storage accounts
  any pod on AKS nodes ──egress public IP──► PostgreSQL (firewall allowlist)
```

The network rules let every node reach these services. Only the identity grants above decide what a pod can actually read or write. Details: [Network access](#network-access).

### Other identities

| Identity | Federated to | Role → scope |
|---|---|---|
| `ai-sdlc-control-plane-mi` | AKS control plane | Managed Identity Operator → kubelet identity; Network Contributor → nodes subnet, egress IP |
| `ai-sdlc-kubelet-mi` | AKS nodes | AcrPull → registry |
| `ai-sdlc-agent-images-github-push-mi` | GitHub `ai-native-sdlc-agent-images`, `production` environment | AcrPush → registry |
| `ai-sdlc-platform-services-github-push-mi` | GitHub `ai-native-sdlc-platform-services`, `production` environment | AcrPush → registry |
| `ai-sdlc-github-broker-github-push-mi` | GitHub `ai-native-sdlc-github-broker`, `production` environment | AcrPush → registry |
| `platform-stop-github-mi` | GitHub, this repo's `main` branch | Azure Kubernetes Service Contributor Role → cluster; Contributor → PostgreSQL server |
| Key Vault CSI add-on identity | AKS-managed, on every node | None |

## Unverified

Open checks; completed ones are in the [verification log](./docs/verification-log.md). No Azure or cluster commands were run by the agent.

- [ ] #36 human-run plan adds exactly eight resources: one SecretProviderClass, one ClusterRole and binding, one Role and binding, one managed identity, its federated credential and one AcrPush assignment; no existing resources change.
- [ ] #36 broker CSI mount reads the App key as file `token-broker-gh-app-private-key` without logging it; actual mount requires the broker Deployment from its own repository.
- [ ] #36 broker repository's `production` workflow exchanges its OIDC token and pushes to ACR using `github_workflows.github_broker.client_id`; no cluster identity gets push.
- [ ] #36 broker RBAC after human apply (default namespace names below):

  ```sh
  kubectl auth can-i create tokenreviews --as=system:serviceaccount:github-broker:token-broker # yes
  kubectl auth can-i get pods -n agents --as=system:serviceaccount:github-broker:token-broker # yes
  kubectl auth can-i get secrets -n agents --as=system:serviceaccount:github-broker:token-broker # no
  kubectl auth can-i list pods -n agents --as=system:serviceaccount:github-broker:token-broker # no
  ```

- [ ] Key Vault seed command against Azure: creates missing placeholders, preserves Portal-created versions on rerun, and fails cleanly if firewall/RBAC denies access. Verified offline with mocked CLI calls only.
- [ ] #19 identity retirement: removal of old federations/grants, including the vault-wide broker grant; no secret values modified.
- [ ] #26: planner fails to read `agent-gpg-private-key` directly with its own identity. Not attempted; the grant listing shows planner has no grant on it.
- [ ] IMDS still blocked from `agents` pods after the workload identity and CSI changes. `deny-imds` is unchanged since #4 but was not re-tested.
- [ ] `foreman`: an unrelated ServiceAccount cannot mount `foreman-admin-token` using foreman's identity; `foreman` cannot get/list/update/patch/delete Secrets or read Workflows.
- [ ] `platform-services-mi` reads only its admin/HMAC secrets (grants not listed); `gh-token-broker-mi` can read the GitHub App private key but not those secrets (broker not built).
- [ ] The SecretProviderClass CRD exists before `make plan-k8s`. `kubernetes_manifest` needs its schema at plan time; on a new cluster, apply the cluster stage (CSI add-on) first.
- [ ] Argo database roles and authentication ([#33](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/33)).
- [ ] CRD version upgrades, uninstall/reinstall and the sample devcontainer Helm feature build.
- [ ] Monitoring table selection, ConfigMap filters, observed ingestion volume and cap behavior. Successful resource deployment does not prove logs are flowing or filtering correctly.
- [ ] Identity continuity across a cluster rebuild.
