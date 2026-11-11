# Deployment

How to deploy and operate this repo's infrastructure. The resources it creates are listed in the [README](../README.md#what-gets-deployed).

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
- Apply `module.kubernetes` immediately after the cluster stage: it installs the monitor agent ConfigMap. See [monitoring costs](./monitoring.md).

> [!NOTE]
> **Regions**: Defaults to `westeurope`; see [`defaults.auto.tfvars`](../defaults.auto.tfvars). PostgreSQL is pinned to `northeurope` because this subscription cannot provision it in West Europe. Log Analytics and the Container Insights data collection rule are also pinned to `northeurope` and must share a region.

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

## Install Argo Workflows

After applying the Kubernetes module (including the controller Roles and RoleBindings):

```sh
make create-argo-executor-token
make install-argo
env -u ARGO_SERVER argo submit --namespace agents --watch workflows/argo-hello-world.yaml
```

- Pins chart **2.0.16**, controller/executor **v4.1.6**, matching the tested CLI. [Values](../helm/argo-workflows/values.yaml) reuse Terraform's controller ServiceAccount and create no ServiceAccounts or RBAC.
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

  Applies [`manifests/argo-executor-token.yaml`](../manifests/argo-executor-token.yaml) to `AGENTS_NAMESPACE` (default `agents`). Run after the Kubernetes module apply and before submitting workflows. Rerunning applies the same metadata without replacing the token. The Secret stored in Key Vault does not create this Kubernetes Secret.

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
  - Secret names and the bootstrap value are editable at the top of [`scripts/init-kv-secrets.sh`](../scripts/init-kv-secrets.sh).
  - Creates `platform-services-admin-token`, `platform-services-hmac-key`, `token-broker-gh-app-private-key`, `agent-gpg-private-key`, `agent-gpg-public-key`, `agent-gpg-fingerprint`, `julieio-goose-github-pat`, `vercel-ai-gateway-api-key` and `argo-executor-token` with the literal placeholder `INIT-ONLY-CHANGE-ME`.
  - To populate the admin token, HMAC key and GPG values, set `AGENT_GPG_USER_NAME` and `AGENT_GPG_USER_EMAIL` in git-ignored `scripts/.env`, then run `make reset-sdlc-secrets` from the repository root. Requires `openssl`, `gpg` and `gpgconf` as well as Azure CLI.
  - Reset creates two independent 32-byte random values (base64) and an Ed25519 signing key valid for one year, without a passphrase for unattended use. It creates new versions even when real values already exist. Updates are sequential: a failure can leave a partial reset.
  - Populate `token-broker-gh-app-private-key`, `julieio-goose-github-pat`, `vercel-ai-gateway-api-key` and `argo-executor-token` by hand in the Azure Portal; reset leaves these untouched.
  - Initialization skips existing secrets. Run one initialization command at a time, before replacing values: the list/create sequence is not atomic.
  - Values are never managed or read by Terraform, so they do not enter Terraform state.

