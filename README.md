# AI-native SDLC — Infrastructure

Terraform for the AI SDLC platform on Azure: one AKS cluster plus the backing services it needs. Single environment (dev).

> [!IMPORTANT]
> All five infrastructure modules were deployed successfully by the human developer on 2026-10-22. Argo hello-world succeeded on 2026-11-05; platform services and agent workflows have not been tested. Agents verify offline only; see [Unverified](#unverified).

## Modules

Apply one at a time, in this order. Each depends on the outputs of the ones before it.

| # | Module | Resource group | Creates |
|---|---|---|---|
| 1 | [`networking`](./modules/networking/) | `ai-sdlc-networking-rg` | VNet, `aks-nodes-subnet` (service endpoints: Key Vault, Storage), empty `AzureFirewallSubnet`, ingress + egress static IPs |
| 2 | [`shared`](./modules/shared/) | `ai-sdlc-shared-rg` | PostgreSQL Flexible Server (`workflow`, `argo` DBs), Blob Storage: `ai-sdlc{suffix}artifacts` (artifact service), `ai-sdlc{suffix}argo` (Argo artifact repository), Key Vault, ACR (pull only), Log Analytics (North Europe) |
| 3 | [`identities`](./modules/identities/) | `ai-sdlc-identities-rg` | Persistent control-plane, kubelet, platform workload and agent secret-read identities; role assignments for networking, ACR, Storage and Key Vault |
| 4 | [`cluster`](./modules/cluster/) | `ai-sdlc-cluster-rg` | AKS (`system`, `platform` and `agents` pools, Cilium data plane and network policy, Key Vault CSI driver), cluster-specific workload federation, Container Insights, cluster-admin role assignment |
| 5 | [`kubernetes`](./modules/kubernetes/) | — | Namespaces `platform`, `argo`, `github-broker`, `agents` (Pod Security `baseline` on `agents`); ServiceAccounts; `argo-executor` ServiceAccount + Role; IMDS-blocking NetworkPolicy on `agents`; trusted `foreman` Secret-create RBAC and admin-token CSI configuration; planner/coder secret CSI configuration; monitor agent ConfigMap |
| 6 | [`platform_stop_mi`](./modules/platform_stop_mi/) | Existing `ai-sdlc-identities-rg` (data lookup) | GitHub OIDC managed identity, federation for `main`, AKS Contributor on the cluster and Contributor on the PostgreSQL server |

Resource group names carry no random suffix. AKS creates its Azure-managed node resources in `ai-sdlc-aks-managed-rg`. Globally unique names (Key Vault, Storage, ACR, Postgres) and the cluster carry a random 4-character suffix, kept in state.

## Prerequisites

- `terraform` ≥ 1.10, `az`, `kubelogin`, `kubectl`, `jq`
- For Argo: `helm` (tested locally with 4.3.1) and the Argo CLI 4.1.6. The sample devcontainer includes the Helm feature; its build has not been exercised here.
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

`-target` is used for staging only. The final untargeted `plan` confirms nothing was missed.

Cluster commands use the separate `cluster` root output, which depends only on `module.cluster`. The combined `summary` output may not be saved until the Kubernetes stage is applied. After adding the `cluster` output to an already deployed cluster, rerun `make plan-cluster`, review the plan, and run `make apply` to save it before `make kubecontext`.

Managed identity names have no random suffix. Identities and their role assignments on shared resources survive cluster rebuilds. Cluster recreation updates workload federation to its OIDC issuer. The identity resource group, control-plane, kubelet and workload identities have `prevent_destroy` guards.

> [!IMPORTANT]
> Before applying this module split, discard any earlier saved plan and generate a fresh one. `moved.tf` preserves Terraform addresses, but existing identities in the cluster resource group would still require replacement to use the new group; `prevent_destroy` blocks that replacement. If identities have already been deployed, review a separate migration before applying.

> [!NOTE]
> **Cilium ([#4](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/4)).** The deployed cluster was switched in place on 2026-10-24; the apply reimaged all pools (about 9 minutes). New clusters get Cilium at creation. Switching back to the `azure` data plane forces cluster replacement.

> [!NOTE]
> **Regions**: Defaults to `westeurope`; see [`defaults.auto.tfvars`](./defaults.auto.tfvars). PostgreSQL is pinned to `northeurope` because this subscription cannot provision it in West Europe. Log Analytics and the Container Insights data collection rule are also pinned to `northeurope` and must share a region.

### Start and stop the platform

With Azure CLI signed into the deployment subscription:

```sh
make stop-platform    # AKS, then PostgreSQL
make start-platform   # PostgreSQL, then AKS
make stop-database    # PostgreSQL only
make start-database
make stop-cluster     # AKS only (existing command)
make start-cluster
```

`AKS_RESOURCE_GROUP`, `AKS_CLUSTER_NAME`, `POSTGRES_RESOURCE_GROUP` and `POSTGRES_SERVER_NAME` default to the local `platform_stop` Terraform output; override them in your shell or as Make variables. The commands fail before calling Azure if a value is empty. Start/stop commands call Azure CLI directly and wait for completion. Local platform commands start PostgreSQL before AKS and stop AKS before PostgreSQL; a failed command stops the sequence. Start the platform before running Terraform against Kubernetes resources.

The **Platform stop** GitHub workflow is manual-only and stops AKS and PostgreSQL in parallel jobs. After the cluster exists, run `make init`, then review `make plan-platform-stop` and run `make apply`. The deployer needs permission to create managed identities/federation in the identities group and assign roles on both target resources. The module uses AzureRM, with no new provider or credentials.

Copy `terraform output -json platform_stop` values into repository Actions variables. The output uses the workflow's `AZ_POSTGRES_RESOURCE_GROUP` / `AZ_POSTGRES_SERVER_NAME` names; local Make commands use `POSTGRES_RESOURCE_GROUP` / `POSTGRES_SERVER_NAME`. OIDC trusts this repository's `main` branch using GitHub's default subject format. The built-in roles also allow modification/deletion, scoped to the individual resources; no ACR push is granted. No saved Azure credential or Terraform state is needed by the workflow. Scheduling is deferred to [#14](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/14).

[AKS considerations](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster): restart depends on capacity; wait 15–30 minutes after stopping before starting. Standalone pods are deleted. [PostgreSQL restarts automatically after seven days](https://learn.microsoft.com/en-us/azure/postgresql/configure-maintain/how-to-stop-server); storage and other retained services remain billable.

### Node pools

| Pool | VM size | Minimum nodes | Maximum nodes |
|---|---|---:|---:|
| `system` | `Standard_D2s_v5` | 1 | 2 |
| `platform` | `Standard_D2s_v5` | 1 | 2 |
| `agents` | `Standard_D4s_v5` | 1 | 2 |

The human developer reported successful deployment with this POC sizing on 2026-10-22. This is provisioning evidence for this subscription/region, not a production sizing recommendation.

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

The four namespaces separate platform services, Argo, the GitHub broker and agent workflows. The broker has its own ServiceAccount and Key Vault secret mounts, including the GitHub App private key.

| Namespace | What goes here |
|---|---|
| `platform` | Platform-services app (workflow and artifact APIs), using ServiceAccount `platform-services` and managed identity `platform-services-mi`. |
| `argo` | Argo Workflows controller and server, with their workload-identity ServiceAccounts. |
| `github-broker` | GitHub token broker, with its workload-identity ServiceAccount (`token-broker`). |
| `agents` | Agent workflow pods; ServiceAccounts for `planner`, `coder`, `reviewer` and `open-pr`; `argo-executor` ServiceAccount and RBAC; trusted `foreman` ServiceAccount with its own workload identity and Secret-create RBAC. Among agent roles, `planner` and `coder` have separate identities with secret-scoped read access (#26); reviewer and open-pr have no identity. |

Agent pods run LLM-driven code, so `agents` has two extra controls:

- **Pod Security `baseline`, enforced.** Rejects `hostNetwork`, `privileged`, `hostPath`, host ports and capabilities beyond the container runtime defaults, so no Docker-in-Docker. `restricted` is warn/audit only: `kubectl apply` prints what templates would need for it.
- **NetworkPolicy `deny-imds`.** Allows all egress except `169.254.169.254`, so pods can't get tokens for node identities such as the kubelet's. Only IMDS is blocked: agents still reach every pod and the internet.

The platform also blocks some addresses itself. For example, [WireServer](https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16) (`168.63.129.16`, the VM agent's channel to Azure) times out from `agents` pods on ports 80 and 32526, verified 2026-10-25. `deny-imds` doesn't cause this, and this repo doesn't enforce it.

### Install Argo Workflows

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
- `make uninstall-argo` removes only the Helm release. CRDs, Workflow objects, the executor token Secret and Terraform resources remain. Workflow management stops until the controller is reinstalled.

### After apply — manual steps

Kept out of Terraform so secrets never land in state, or because no azurerm resource covers it.

- **Argo executor token Secret.** Argo mounts it into the executor containers of agent pods. Legacy non-expiring token — kept out of Terraform state:

  ```sh
  make create-argo-executor-token
  ```

  Applies [`manifests/argo-executor-token.yaml`](./manifests/argo-executor-token.yaml) to `AGENTS_NAMESPACE` (default `agents`, matching Terraform). Run after the Kubernetes module apply and before submitting workflows. Rerunning applies the same metadata without replacing the token. The Secret stored in Key Vault does not create this Kubernetes Secret.

- [**Postgres roles for workload identities.**](https://learn.microsoft.com/en-us/azure/postgresql/security/security-manage-entra-users?source=recommendations) As the Entra admin, create the app role for `platform-services-mi` (not the retired `workflow-service-mi`). Use its `principal_id` from `terraform output -json summary` → `identities.workloads["platform-services"]`:

  ```sql
  SELECT * FROM pg_catalog.pgaadauth_create_principal_with_oid(
    'platform-services-mi', '<principal_id>', 'service', false, false
  );
  ```

  Grant this role the app's required access in the `workflow` database. Argo still needs separate roles for `argo-workflow-controller-mi` and `argo-server-mi` in its `argo` database, using their own principal IDs. The function and managed-identity object type are [documented by Microsoft](https://learn.microsoft.com/en-us/azure/postgresql/security/security-manage-entra-users#create-a-role-by-using-the-microsoft-entra-id-object-identifier); database grants and authentication remain unverified on this deployment.
- **Local-dev service principal credential.** `{name}-local-dev` has no secret in Terraform. Run `make local-dev-credential` (`az ad app credential reset --append --years 1`), copy the secret from the terminal into a password manager or git-ignored file, and keep it out of the repo.
- **Key Vault secrets.** After the shared module apply, run `make init-kv-secrets` with your Azure CLI login and an allowed admin IP. It reads the vault name from the saved `summary.shared.key_vault.name` output; if that output is not saved yet, use `KEY_VAULT_NAME=<vault-name> make init-kv-secrets`.
  - Secret names and the bootstrap value are editable at the top of [`scripts/init-kv-secrets.sh`](./scripts/init-kv-secrets.sh).
  - Creates `platform-services-admin-token`, `platform-services-hmac-key`, `token-broker-gh-app-private-key`, `agent-gpg-private-key`, `agent-gpg-public-key`, `agent-gpg-fingerprint`, `julieio-goose-github-pat`, `vercel-ai-gateway-api-key` and `argo-executor-token` with the literal placeholder `INIT-ONLY-CHANGE-ME`.
  - To populate the admin token, HMAC key and GPG values, set `AGENT_GPG_USER_NAME` and `AGENT_GPG_USER_EMAIL` in git-ignored `scripts/.env`, then run `make reset-sdlc-secrets` from the repository root. Requires `openssl`, `gpg` and `gpgconf` as well as Azure CLI. Reset reads the vault name from the saved Terraform summary output.
  - Reset creates two independent 32-byte random values (base64) and an Ed25519 signing key valid for one year, without a passphrase for unattended use. It uploads the armored private/public keys and fingerprint from private temporary files; its temporary GPG home and agent are cleaned up on exit without importing into the existing keyring. It creates new versions even when real values already exist. Updates are sequential: a failure can leave a partial reset.
  - Populate `token-broker-gh-app-private-key`, `julieio-goose-github-pat`, `vercel-ai-gateway-api-key` and `argo-executor-token` by hand in the Azure Portal; reset leaves these untouched. The initialization placeholder is not a generated credential or key.
  - Initialization lists secret names only, skips existing secrets, and suppresses the set response. Listing or creation errors stop the command; rerun after fixing the error. Run one initialization command at a time, before replacing values: the list/create sequence is not atomic.
  - Values are never managed or read by Terraform, so they do not enter Terraform state. These targets add no workload role assignments; access grants remain separate work.

### Identity replacements (#19)

The human developer reported a successful apply on 2026-11-05 after reviewing the plan. The change replaces `workflow-service-mi` and `artifact-service-mi` with `platform-services-mi`, replaces `token-broker-mi` with `gh-token-broker-mi`, and adds `foreman-mi`. The shared workload-identity `prevent_destroy` block is restored following that apply. Runtime access checks remain in **Unverified** below.

### Trusted foreman step (#19)

- Key Vault values were populated under #21; do not rerun initialization/reset for this change. Terraform only configures names, grants and CSI references.
- `foreman-mi` reads only `platform-services-admin-token`; `platform-services-mi` reads that token and `platform-services-hmac-key`. `gh-token-broker-mi` reads only `token-broker-gh-app-private-key`. Each Key Vault grant is at secret scope; the old vault-wide broker grant is removed. Names are in `key_vault_secret_names` in `defaults.auto.tfvars`.
- The workflows repo must run the trusted step as `foreman` in `agents`, label its pod `azure.workload.identity/use: "true"`, and mount the read-only CSI volume using SecretProviderClass `foreman-admin-token` (root variable `foreman_secret_provider_class_name`) into the main container only. No admin-token Kubernetes Secret synchronization is configured.
- The trusted main container needs its Kubernetes API ServiceAccount token to create the per-step Secrets; it is separate from the Azure federation token and the Argo executor token. If the template disables automount, it must explicitly project the API token for this container. Keep the executor's existing permissions separate.
- Create each HMAC Secret with a same-namespace Workflow ownerReference using `{{workflow.name}}` and `{{workflow.uid}}`, and `blockOwnerDeletion: false`. No Workflow-read or finalizer permissions are needed. The Role grants only `secrets: create`; it permits any Secret name in `agents`, accepted because this step is trusted. The agent steps mount only their own HMAC Secret; tokens never go through Argo parameters.
- `deny-imds` stays unchanged. CSI workload identity does not need workload-pod IMDS access. This policy permits other egress; adding a narrower allow policy would not restrict it because NetworkPolicies are additive.
- Platform-services must use SA `platform-services` in `platform`. The broker keeps SA `token-broker` in `github-broker`, now annotated for `gh-token-broker-mi`. Container images, WorkflowTemplates and the API endpoint are maintained outside this repo.

### Planner and coder secret mounts (#18, #26)

Terraform manages references to existing Key Vault secrets only. The real values were populated under #21; do not rerun initialization/reset.

| ServiceAccount / identity | SecretProviderClass | Mounted file names |
|---|---|---|
| `coder` / `coder-mi` | `coder-secrets` | `agent-gpg-private-key`, `julieio-goose-github-pat`, `vercel-ai-gateway-api-key` |
| `planner` / `planner-mi` | `planner-secrets` | `julieio-goose-github-pat`, `vercel-ai-gateway-api-key` |

- Each identity has only `Key Vault Secrets User`, assigned separately on each listed secret. Planner cannot read the signing key. Reviewer and open-pr have no federation or client-ID annotation. Agent API-token automount remains off.
- Root `agent_secret_provider_class_names` selects the two roles and their class names; `key_vault_secret_names` supplies object/file names. These replace the coder-specific inputs; update any personal overrides. The existing coder identity, federation and signing grant are retained; the CSI class is renamed to `coder-secrets` to cover all three credentials. Terraform may recreate the CSI resource at its new manifest address. No state-migration block is maintained for this non-production cluster.
- Apply identities, cluster and Kubernetes stages in that order, reviewing each plan. The cluster/CSI CRD must exist before Kubernetes planning. Only the human developer runs these commands.
- In the workflows repo, set `serviceAccountName` to the role and label the pod `azure.workload.identity/use: "true"`. Add a read-only CSI volume using the matching class and mount it in the main container only. The example uses coder; for planner use `planner` and `planner-secrets`.

```yaml
# Pod metadata:
metadata:
  labels:
    azure.workload.identity/use: "true"
# Pod spec fragment:
spec:
  serviceAccountName: coder
  automountServiceAccountToken: false
  volumes:
    - name: agent-secrets
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: coder-secrets
  # Add to the existing main container's volumeMounts only:
  # - name: agent-secrets
  #   mountPath: /mnt/agent-secrets
  #   readOnly: true
```

- Files appear under `/mnt/agent-secrets/<object-name>`. The agent entrypoint maps the PAT to `GH_TOKEN` and the gateway key to `AI_GATEWAY_API_KEY`; coder imports the private key into its private GPG home. Do not print values or pass them through Argo parameters. No Kubernetes Secret synchronization is configured. Entrypoint and Argo template changes belong to other repos.
- The PAT is deliberately shared with planner: it can push within its token permissions. Main-branch rulesets still require a PR and signed commits; they do not make planner read-only. The token broker is the deferred replacement ([#26](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/26)).
- Keep `deny-imds` and foreman unchanged. CSI uses workload identity; the node CSI add-on identity gets no grant. Per-run HMAC tokens remain with foreman.
- **ADR discrepancy:** [ADR-003](https://github.com/julie-ng/ai-native-sdlc/blob/main/architecture/decisions/003-platform-services-vs-agent-pods.md) still limits the exception to the signing key. The human decision in #26 (2026-11-07) supersedes that limit for these long-lived secrets; the parent ADR update is pending.

### Platform-services secret mount

- SecretProviderClass `platform-services-secrets` in `platform` uses the existing `platform-services-mi` identity for ServiceAccount `platform-services`.
- Mount it read-only at `/mnt/secrets` to read `platform-services-admin-token` and `platform-services-hmac-key` (the configured Key Vault object names). No Kubernetes Secret synchronization is configured.
- The Deployment, workload-identity pod label and volume mount live in [platform-services](https://github.com/julie-ng/ai-native-sdlc-platform-services/issues/45).

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
| ACR | Public endpoint. Basic SKU has no network rules. Kubelet pulls; nothing in this repo or GitHub can push — images are pushed manually. |

Egress: all cluster outbound traffic leaves via `ai-sdlc-egress-ip` (load balancer outbound IP). No egress filtering, except IMDS for `agents`.

## Unverified

Provisioning confirmed by the human developer on 2026-10-22: networking, shared services (including PostgreSQL 17/B1ms in North Europe), identities and role assignments, all three AKS pools, and the Kubernetes module. The custom resource groups and staged applies were accepted. No Azure or cluster commands were run by the agent to independently verify runtime behavior.

POC verification checklist (results reported by the human developer):

- [x] `make stop-cluster` completes successfully.
- [x] Final untargeted `make plan` shows no pending changes after all stages.
- [x] `make start-cluster`, node readiness, and `make kubecontext` after restart. Start the cluster before planning or applying Kubernetes resources.
- [x] Platform/database start and stop using configured resource names.
- [x] New `platform_stop_mi` module: identities-group lookup, identity/federation creation, built-in role assignments and first manual stop workflow. 
- [x] `local-dev` service principal: Entra app registration created by the applying identity, credential created with `make local-dev-credential`, and user delegation SAS URLs generated with it against the `artifacts` account.
- [x] `make reset-sdlc-secrets`: human developer ran it and verified the resulting values in Azure Portal on 2026-11-05; `token-broker-gh-app-private-key` remained unchanged. Temporary GPG isolation/cleanup and key properties were checked offline with mocked uploads.
- [ ] Key Vault seed command against Azure: creates missing placeholders, preserves Portal-created versions on rerun, and fails cleanly if firewall/RBAC denies access. Verified offline with mocked CLI calls only.
- [ ] #19 identity replacement and retirement: human-reviewed destroy list and removal of old federations/grants, including the vault-wide broker grant; no secret values modified.
- [ ] #26 provisioning: review the four new secret-scoped grants, planner/coder-only federation and annotations, retained coder signing grant and any CSI resource recreation. Reviewer/open-pr have no identity; existing platform grants are unchanged.
- [ ] #26 CSI positive/negative checks: labeled coder and planner pods mount their three/two files while IMDS remains blocked; verify files are nonempty without printing values. Planner must fail to read `agent-gpg-private-key` directly using its own identity, and must fail to mount coder's class. Inspect mount events for authentication failure.
- [ ] #18 least privilege: coder's signing identity cannot read the admin/HMAC or GitHub App secrets; commit signing from the mounted key succeeds. Agent entrypoint/GPG import and Argo volume configuration are maintained outside this repo.
- [ ] `foreman` CSI admin-token mount succeeds while IMDS remains blocked; an unrelated ServiceAccount cannot mount it using foreman's identity.
- [ ] `foreman` can create HMAC Secrets but cannot get/list/update/patch/delete Secrets or read Workflows; deleting a test Workflow garbage-collects its Secrets.
- [ ] `platform-services-mi` authenticates to PostgreSQL and Blob and reads only its admin/HMAC secrets; `gh-token-broker-mi` can read the GitHub App private key but not those secrets.
- [ ] #29: human-run plan adds only `platform-services-secrets`; after apply, the labeled `platform-services` pod in `platform` mounts nonempty `platform-services-admin-token` and `platform-services-hmac-key` files at `/mnt/secrets` without printing values. Deployment lives in platform-services.
- [ ] The SecretProviderClass CRD exists before `make plan-k8s`. `kubernetes_manifest` needs its schema at plan time; on a new cluster, apply the cluster stage (CSI add-on) first.
- [ ] Workload identity authentication to Blob, Key Vault and PostgreSQL, including the manual database roles and Kubernetes workload labels.
- [x] Human applied the four controller RBAC resources, installed chart 2.0.16 / Argo v4.1.6, and created the executor token Secret on 2026-11-05. Workflow `hello-world-7xzjr` succeeded in `agents` as `planner` (1/1 step, 20 seconds), confirming executor result reporting under `deny-imds`.
- [x] Human confirmed hello-world on `aks-agents-39765645-vmss000008`, controller on `aks-platform-20300205-vmss000009` (Running, 0 restarts), and a successful repeat `make install-argo` (release revision 2) on 2026-11-05.
- [ ] Agent workflows, executor-only token mount inspection and application integrations remain untested.
- [ ] CRD version upgrades, uninstall/reinstall and the sample devcontainer Helm feature build have not been exercised.
- [ ] Monitoring table selection, ConfigMap filters, observed ingestion volume and cap behavior. Successful resource deployment does not prove logs are flowing or filtering correctly.
- [ ] Identity continuity across a cluster rebuild; this lifecycle has not been exercised yet.

Agent pod restrictions ([#4](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/4)), results reported by the human developer on 2026-10-25 ([details](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/4#issuecomment-6394927018)):

- [x] `make plan-cluster` showed an in-place update, not a replace. Cilium runs on every node; no kube-proxy pods.
- [x] From a pod in `agents`, IMDS instance metadata and token requests time out (`curl -s -H Metadata:true --connect-timeout 10 "http://169.254.169.254/metadata/instance?api-version=2023-11-15"`).
- [x] Control: the same request from a pod in `default` returns metadata, so the policy is what blocks `agents`.
- [x] From the `agents` pod, `curl https://github.com` returns `200`, `getent hosts kubernetes.default.svc.cluster.local` resolves, and the API server answers `401`.
- [x] A pod with `hostNetwork: true` in `agents` is rejected: `violates PodSecurity "baseline:latest"`.
- [x] `kubectl get netpol deny-imds -n agents -o yaml` shows `namespaceSelector: {}`.
- [x] Container Insights still collects after the switch: `KubePodInventory` shows the test pod in `agents`.
- [x] Node identities: all pools carry the kubelet identity (`AcrPull` on the registry only) and the Key Vault CSI add-on identity (no role assignments). No Container Insights identity is attached.

## Docs

- [Decisions](./docs/decisions.md) — decision log for this repo
- [Inventory](./docs/inventory.md) — resource groups and conventions from the earlier cloudkube repos this is based on
