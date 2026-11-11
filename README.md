# AI-native SDLC — Infrastructure

Terraform for the AI SDLC platform on Azure: one AKS cluster plus the backing services it needs. Single environment (dev).

> [!IMPORTANT]
> All infrastructure modules were deployed successfully by the human developer on 2026-10-22. Argo hello-world succeeded on 2026-11-05; platform services and agent workflows have not been tested. Agents verify offline only; see [Unverified](#unverified).

## Modules

Apply one at a time, in this order. Each depends on the outputs of the ones before it.

| # | Module | Resource group | Creates |
|---|---|---|---|
| 1 | [`networking`](./modules/networking/) | `ai-sdlc-networking-rg` | VNet, `aks-nodes-subnet` (service endpoints: Key Vault, Storage), empty `AzureFirewallSubnet`, ingress + egress static IPs |
| 2 | [`shared`](./modules/shared/) | `ai-sdlc-shared-rg` | PostgreSQL Flexible Server (`workflow`, `argo` DBs), Blob Storage: `aisdlc{suffix}artifacts` (artifact service), `aisdlc{suffix}argo` (Argo artifact repository), Key Vault, ACR, Log Analytics (North Europe) |
| 3 | [`identities`](./modules/identities/) | `ai-sdlc-identities-rg` | Persistent control-plane, kubelet, workload and GitHub push identities; role assignments for networking, ACR, Storage and Key Vault |
| 4 | [`cluster`](./modules/cluster/) | `ai-sdlc-cluster-rg` | AKS (`system`, `platform` and `agents` pools, Cilium data plane and network policy, Key Vault CSI driver), workload identity federation, Container Insights, cluster-admin role assignment |
| 5 | [`kubernetes`](./modules/kubernetes/) | — | Namespaces, ServiceAccounts, `argo-executor` and `foreman` RBAC, IMDS-blocking NetworkPolicy on `agents`, SecretProviderClasses, monitor agent ConfigMap |
| 6 | [`platform_stop_mi`](./modules/platform_stop_mi/) | Existing `ai-sdlc-identities-rg` (data lookup) | GitHub OIDC managed identity, federation for `main`, AKS Contributor on the cluster and Contributor on the PostgreSQL server |

Resource group names carry no random suffix. AKS creates its Azure-managed node resources in `ai-sdlc-aks-managed-rg`. Globally unique names (Key Vault, Storage, ACR, Postgres) and the cluster carry a random 4-character suffix, kept in state.

## Prerequisites

- `terraform` ≥ 1.10, `az`, `kubelogin`, `kubectl`, `jq`
- For Argo: `helm` (tested locally with 4.3.1) and the Argo CLI 4.1.6.
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
make plan-k8s        && make apply
make plan-platform-stop && make apply
make plan            # expect: no changes
```

- `-target` is used for staging only. The final untargeted `plan` confirms nothing was missed.
- Cluster commands use the separate `cluster` root output, which depends only on `module.cluster`. The combined `summary` output may not be saved until the Kubernetes stage is applied.
- Identities and their role assignments on shared resources survive cluster rebuilds. Cluster recreation updates workload federation to its OIDC issuer. The identity resource group and all managed identities have `prevent_destroy` guards.
- Apply `module.kubernetes` immediately after the cluster stage: it installs the monitor agent ConfigMap. See [monitoring costs](./docs/monitoring.md).

> [!NOTE]
> **Regions**: Defaults to `westeurope`; see [`defaults.auto.tfvars`](./defaults.auto.tfvars). PostgreSQL is pinned to `northeurope` because this subscription cannot provision it in West Europe. Log Analytics and the Container Insights data collection rule are also pinned to `northeurope` and must share a region.

### Start and stop the platform

With Azure CLI signed into the deployment subscription:

```sh
make stop-platform    # AKS, then PostgreSQL
make start-platform   # PostgreSQL, then AKS
make stop-database    # PostgreSQL only
make start-database
make stop-cluster     # AKS only
make start-cluster
```

- `AKS_RESOURCE_GROUP`, `AKS_CLUSTER_NAME`, `POSTGRES_RESOURCE_GROUP` and `POSTGRES_SERVER_NAME` default to the local `platform_stop` Terraform output; override them in your shell or as Make variables. The commands fail before calling Azure if a value is empty.
- Start the platform before running Terraform against Kubernetes resources.
- The **Platform stop** GitHub workflow is manual-only and stops AKS and PostgreSQL in parallel jobs. Copy `terraform output -json platform_stop` values into repository Actions variables. The output uses the workflow's `AZ_POSTGRES_RESOURCE_GROUP` / `AZ_POSTGRES_SERVER_NAME` names. OIDC trusts this repository's `main` branch. Scheduling is deferred to [#14](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/14).
- [AKS considerations](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster): restart depends on capacity; wait 15–30 minutes after stopping before starting. Standalone pods are deleted. [PostgreSQL restarts automatically after seven days](https://learn.microsoft.com/en-us/azure/postgresql/configure-maintain/how-to-stop-server); storage and other retained services remain billable.

### Node pools

| Pool | VM size | Minimum nodes | Maximum nodes |
|---|---|---:|---:|
| `system` | `Standard_D2s_v5` | 1 | 2 |
| `platform` | `Standard_D2s_v5` | 1 | 2 |
| `agents` | `Standard_D4s_v5` | 1 | 2 |

POC sizing, not a production recommendation. All pools autoscale within these bounds; use start/stop when idle. User-pool scale-to-zero is a [deferred target design (#3)](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/3). Scheduling labels and taints for workloads: see [workload integration](./docs/workload-integration.md#scheduling).

## Identities and access

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
         ◄┄┄ SQL ┄┄┄   PostgreSQL role + GRANTs (manual, see "After apply"; not Azure RBAC)
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

Rows are the narrowest scope a grant can land on. Empty = no access.

```
                                    platform  foreman  gh-token  argo-wf     argo     planner  coder
                                    services           broker    controller  server
                                    ────────  ───────  ────────  ──────────  ───────  ───────  ─────
KEY VAULT (secret scope)
  platform-services-admin-token        R         R
  platform-services-hmac-key           R
  token-broker-gh-app-private-key                         R
  agent-gpg-private-key                                                                         R
  julieio-goose-github-pat                                                              R       R
  vercel-ai-gateway-api-key                                                             R       R
  agent-gpg-public-key / fingerprint
  argo-executor-token

BLOB STORAGE
  artifacts account                    D
    └ artifacts container              RW
  argo account
    └ argo container                                                 RW         R

POSTGRESQL (SQL roles, manual)
  workflow database                    RW*
  argo database                                                      (#33)     (#33)

R  = Key Vault Secrets User / Storage Blob Data Reader
RW = Storage Blob Data Contributor
D  = Storage Blob Delegator (user-delegation SAS signing key)
*  = CONNECT + CREATE on DB, USAGE + CREATE on schema public; owns its own tables
```

### Network reach

Applies to every pod, not per identity:

```
  any pod on AKS nodes ──service endpoint──► Key Vault, both storage accounts
  any pod on AKS nodes ──egress public IP──► PostgreSQL (firewall allowlist)
```

The network rules let every node reach these services. Only the identity grants above decide what a pod can actually read or write. Details: [Network](#network).

### Other identities

| Identity | Federated to | Role → scope |
|---|---|---|
| `ai-sdlc-control-plane-mi` | AKS control plane | Managed Identity Operator → kubelet identity; Network Contributor → nodes subnet, egress IP |
| `ai-sdlc-kubelet-mi` | AKS nodes | AcrPull → registry |
| `ai-sdlc-agent-images-github-push-mi` | GitHub `ai-native-sdlc-agent-images`, `production` environment | AcrPush → registry |
| `ai-sdlc-platform-services-github-push-mi` | GitHub `ai-native-sdlc-platform-services`, `production` environment | AcrPush → registry |
| `platform-stop-github-mi` | GitHub, this repo's `main` branch | Azure Kubernetes Service Contributor Role → cluster; Contributor → PostgreSQL server |
| Key Vault CSI add-on identity | AKS-managed, on every node | None |

## Kubernetes namespaces

| Namespace | What goes here |
|---|---|
| `platform` | Platform-services app (workflow and artifact APIs) |
| `argo` | Argo Workflows controller and server |
| `github-broker` | GitHub token broker |
| `agents` | Agent workflow pods (`planner`, `coder`, `reviewer`, `open-pr`), the `argo-executor` ServiceAccount and the trusted `foreman` step |

Agent pods run LLM-driven code, so `agents` has two extra controls:

- **Pod Security `baseline`, enforced.** Rejects `hostNetwork`, `privileged`, `hostPath`, host ports and capabilities beyond the container runtime defaults, so no Docker-in-Docker. `restricted` is warn/audit only: `kubectl apply` prints what templates would need for it.
- **NetworkPolicy `deny-imds`.** Allows all egress except `169.254.169.254`, so pods can't get tokens for node identities such as the kubelet's. Only IMDS is blocked: agents still reach every pod and the internet. Workload identity doesn't need IMDS: it uses the projected ServiceAccount token.

## Install Argo Workflows

After applying the Kubernetes module (including the controller Roles and RoleBindings):

```sh
make create-argo-executor-token
make install-argo
env -u ARGO_SERVER argo submit --namespace agents --watch workflows/argo-hello-world.yaml
```

- Pins chart **2.0.16**, controller/executor **v4.1.6**, matching the tested CLI. [Values](./helm/argo-workflows/values.yaml) reuse Terraform's controller ServiceAccount and create no ServiceAccounts or RBAC.
- The install target applies the upstream full CRDs with server-side apply, then runs `helm upgrade --install`. The chart's CRD hook is disabled because it creates its own ServiceAccount and cluster RBAC. CRD installation requires cluster-admin privileges.
- Controller in `argo` on the `platform` pool; `--namespaced --managed-namespace=agents` limits the watch scope. Terraform Roles separately limit workflow access to `agents`, controller config-map reads to `argo`, and Secret reads to the named executor token only.
- Workflow defaults disable token automount, use `argo-executor` for executor containers, and select/tolerate the `agents` pool. Hello-world runs as `planner`. No Argo server/UI, archive, node-status offload or artifact repository is configured. The CLI talks directly to Kubernetes using your kube login.
- `ARGO_NAMESPACE` and `AGENTS_NAMESPACE` in Make must match Terraform's namespace defaults. The values file and hello-world manifest also use those names; update them together if renaming namespaces.
- `make uninstall-argo` removes only the Helm release. CRDs, Workflow objects, the executor token Secret and Terraform resources remain.

## After apply — manual steps

Kept out of Terraform so secrets never land in state, or because no azurerm resource covers it.

- **Argo executor token Secret.** Argo mounts it into the executor containers of agent pods. Legacy non-expiring token, kept out of Terraform state:

  ```sh
  make create-argo-executor-token
  ```

  Applies [`manifests/argo-executor-token.yaml`](./manifests/argo-executor-token.yaml) to `AGENTS_NAMESPACE` (default `agents`). Run after the Kubernetes module apply and before submitting workflows. Rerunning applies the same metadata without replacing the token. The Secret stored in Key Vault does not create this Kubernetes Secret.

- [**Postgres roles for workload identities.**](https://learn.microsoft.com/en-us/azure/postgresql/security/security-manage-entra-users) With Azure CLI signed in as the Entra admin and your IP allowed by the database firewall, [connect using an Entra token](https://learn.microsoft.com/en-us/azure/postgresql/security/security-entra-configure):

  ```sh
  PGPASSWORD="$(az account get-access-token --resource-type oss-rdbms --query accessToken --output tsv)" \
    psql "host=<server>.postgres.database.azure.com port=5432 dbname=postgres user=<entra-admin> sslmode=require"
  ```

  Create the app role for `platform-services-mi`. Use its `principal_id` from `terraform output -json summary` → `identities.workloads["platform-services"]`:

  ```sql
  SELECT * FROM pg_catalog.pgaadauth_create_principal_with_oid(
    'platform-services-mi', '<principal_id>', 'service', false, false
  );
  ```

  As the Entra admin, grant access to `workflow` and its `public` schema:

  ```sql
  GRANT CONNECT, CREATE ON DATABASE workflow TO "platform-services-mi";
  \c workflow
  GRANT USAGE, CREATE ON SCHEMA public TO "platform-services-mi";
  ```

  Enter `\c workflow` on its own line; if pasted together with the next SQL statement, psql reads that statement as connection arguments. The app runs its own startup migrations as `platform-services-mi`, so it owns its tables and the `drizzle` journal schema. Database `CREATE` permits schema creation; schema `CREATE` permits table creation. PostgreSQL 15+ does not grant regular roles `CREATE` on `public` by default ([schema privileges](https://www.postgresql.org/docs/17/ddl-schemas.html#DDL-SCHEMAS-PRIV)).

  Argo roles for `argo-workflow-controller-mi` and `argo-server-mi` in the `argo` database are tracked in [#33](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/33).

- **Local-dev service principal credential.** `{name}-local-dev` has no secret in Terraform. Run `make local-dev-credential` (`az ad app credential reset --append --years 1`), copy the secret from the terminal into a password manager or git-ignored file, and keep it out of the repo.

- **Key Vault secrets.** After the shared module apply, run `make init-kv-secrets` with your Azure CLI login and an allowed admin IP. It reads the vault name from the saved `summary.shared.key_vault.name` output; if that output is not saved yet, use `KEY_VAULT_NAME=<vault-name> make init-kv-secrets`.
  - Secret names and the bootstrap value are editable at the top of [`scripts/init-kv-secrets.sh`](./scripts/init-kv-secrets.sh).
  - Creates `platform-services-admin-token`, `platform-services-hmac-key`, `token-broker-gh-app-private-key`, `agent-gpg-private-key`, `agent-gpg-public-key`, `agent-gpg-fingerprint`, `julieio-goose-github-pat`, `vercel-ai-gateway-api-key` and `argo-executor-token` with the literal placeholder `INIT-ONLY-CHANGE-ME`.
  - To populate the admin token, HMAC key and GPG values, set `AGENT_GPG_USER_NAME` and `AGENT_GPG_USER_EMAIL` in git-ignored `scripts/.env`, then run `make reset-sdlc-secrets` from the repository root. Requires `openssl`, `gpg` and `gpgconf` as well as Azure CLI.
  - Reset creates two independent 32-byte random values (base64) and an Ed25519 signing key valid for one year, without a passphrase for unattended use. It creates new versions even when real values already exist. Updates are sequential: a failure can leave a partial reset.
  - Populate `token-broker-gh-app-private-key`, `julieio-goose-github-pat`, `vercel-ai-gateway-api-key` and `argo-executor-token` by hand in the Azure Portal; reset leaves these untouched.
  - Initialization skips existing secrets. Run one initialization command at a time, before replacing values: the list/create sequence is not atomic.
  - Values are never managed or read by Terraform, so they do not enter Terraform state.

## Network

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

Egress: all cluster outbound traffic leaves via `ai-sdlc-egress-ip` (load balancer outbound IP). No egress filtering, except IMDS for `agents`.

## Unverified

Open checks; completed ones are in the [verification log](./docs/verification-log.md). No Azure or cluster commands were run by the agent.

- [ ] Key Vault seed command against Azure: creates missing placeholders, preserves Portal-created versions on rerun, and fails cleanly if firewall/RBAC denies access. Verified offline with mocked CLI calls only.
- [ ] #19 identity retirement: removal of old federations/grants, including the vault-wide broker grant; no secret values modified.
- [ ] #26 provisioning: review the four new secret-scoped grants, planner/coder-only federation and annotations, retained coder signing grant and any CSI resource recreation. Reviewer/open-pr have no identity; existing platform grants are unchanged.
- [ ] #26 CSI positive/negative checks: labeled coder and planner pods mount their three/two files while IMDS remains blocked; verify files are nonempty without printing values. Planner must fail to read `agent-gpg-private-key` directly using its own identity, and must fail to mount coder's class. Inspect mount events for authentication failure.
- [ ] #18 least privilege: coder's signing identity cannot read the admin/HMAC or GitHub App secrets; commit signing from the mounted key succeeds.
- [ ] `foreman` CSI admin-token mount succeeds while IMDS remains blocked; an unrelated ServiceAccount cannot mount it using foreman's identity.
- [ ] `foreman` can create HMAC Secrets but cannot get/list/update/patch/delete Secrets or read Workflows; deleting a test Workflow garbage-collects its Secrets.
- [ ] `platform-services-mi` authenticates to PostgreSQL and Blob and reads only its admin/HMAC secrets; `gh-token-broker-mi` can read the GitHub App private key but not those secrets.
- [ ] #29: the labeled `platform-services` pod in `platform` mounts nonempty `platform-services-admin-token` and `platform-services-hmac-key` files at `/mnt/secrets` without printing values.
- [ ] The SecretProviderClass CRD exists before `make plan-k8s`. `kubernetes_manifest` needs its schema at plan time; on a new cluster, apply the cluster stage (CSI add-on) first.
- [ ] Argo database roles and authentication ([#33](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/33)).
- [ ] Agent workflows, executor-only token mount inspection and application integrations.
- [ ] CRD version upgrades, uninstall/reinstall and the sample devcontainer Helm feature build.
- [ ] Monitoring table selection, ConfigMap filters, observed ingestion volume and cap behavior. Successful resource deployment does not prove logs are flowing or filtering correctly.
- [ ] Identity continuity across a cluster rebuild.

## Docs

- [Decisions](./docs/decisions-log.md) — decision log for this repo
- [Workload integration](./docs/workload-integration.md) — ServiceAccounts, labels and secret mounts that workloads in other repos must use
- [Monitoring costs](./docs/monitoring.md) — Container Insights collection and cost controls
- [Verification log](./docs/verification-log.md) — checks completed by the human developer
- [Inventory](./docs/inventory.md) — resource groups and conventions from the earlier cloudkube repos this is based on
