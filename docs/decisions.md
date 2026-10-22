# Decision log

Design reasoning lives in the [ADRs](https://github.com/julie-ng/autonomous-agents-setup/tree/main/architecture/decisions) of the parent repo. This log covers infrastructure choices.

## Decisions

| Date | Decision | Why |
|---|---|---|
| 2026-10-22 | One environment, `dev`; base name `aisdlc`, no env in names | POC. |
| 2026-10-22 | One root module calling four modules: networking, shared, cluster, kubernetes. Applied one at a time with `-target` | Staged rollout while testing; one state. Replaces the earlier separate-repo split. |
| 2026-10-22 | Local state | Blind first pass; remote backend later. |
| 2026-10-22 | Azure CLI auth only; no user, tenant or subscription IDs in the repo | Deployer identity from `data.azurerm_client_config`, Postgres admin UPN via `data.azuread_user`. Subscription from `az account set` — azurerm v5.10 requires `subscription_id` only when `use_cli = false` (`internal/provider/provider.go`). Adds the `azuread` provider for one lookup. |
| 2026-10-22 | Region is a variable, `northeurope` placeholder | Region capacity for all services not yet checked. |
| 2026-10-22 | Random 4-character suffix on globally unique names and the cluster; networking and shared groups unsuffixed | Longer lifecycle than the cluster. |
| 2026-10-22 | Public API server, Entra ID only, local accounts off, Azure RBAC | Default endpoint; simplest. |
| 2026-10-22 | Azure CNI Overlay, no network policy engine | Easiest option. No NetworkPolicy yet — nothing restricts pod-to-pod or agent egress inside the cluster. |
| 2026-10-22 | Two node pools: `system` (System mode, `CriticalAddonsOnly` taint), `platform` (User mode) | Target design adds an `agents` pool. For now agents and platform services share `platform`. |
| 2026-10-22 | Egress: load balancer outbound IP (`aisdlc-egress-ip`) | Static Egress Gateway needs a dedicated Gateway-mode pool (≥ 2 nodes for HA, no autoscaler) and a public IP prefix — extra cost ([docs](https://learn.microsoft.com/en-us/azure/aks/configure-static-egress-gateway)). NAT gateway not wanted. |
| 2026-10-22 | Ingress IP created, unused | No inbound webhook, no ingress controller, no DNS zone yet. No role assignment on it. |
| 2026-10-22 | `AzureFirewallSubnet` created empty (`/26`) | Reserves address space for egress control (ADR-002). |
| 2026-10-22 | Key Vault, Storage: service endpoints + default-deny network rules | Backbone routing without private endpoint cost. |
| 2026-10-22 | Two storage accounts: `artifacts` (artifact service), `argo` (Argo artifact repository) | Separate access boundaries: artifact-service and argo identities each get Blob Data Contributor on their own container only. |
| 2026-10-22 | Postgres: public access + firewall rules | Flexible Server supports VNet integration or public access (+ private endpoint) — no service endpoints ([docs](https://learn.microsoft.com/en-us/azure/postgresql/network/concepts-networking-public)). |
| 2026-10-22 | Postgres Entra-only auth | ADR-005: Argo via workload identity, no stored password. |
| 2026-10-22 | Container Insights (managed identity auth) + Log Analytics | Requested minimum observability. DCR + association created explicitly, per [Microsoft's Terraform sample](https://github.com/microsoft/Docker-Provider/tree/ci_prod/scripts/onboarding/aks/onboarding-msi-terraform). |
| 2026-10-22 | Workload identities for `workflow-service`, `artifact-service`, `token-broker`, `argo` only | ADR-003: agent pods get no cloud identity. |
| 2026-10-22 | Terraform creates ServiceAccounts; Helm charts reference them by name | Federated credential subjects are then fixed by this repo, not by chart defaults. |
| 2026-10-22 | No secrets in Terraform | Values would land in state. Added manually after apply. |
| 2026-10-22 | azurerm `~> 5.10`, kubernetes `~> 3.4` | Latest at time of writing. 5.x renames several arguments and requires `node_provisioning_profile` on AKS. |

## Accepted trade-offs

| Trade-off | Notes |
|---|---|
| Postgres traffic over the public internet | TLS enforced by the service; firewall limits sources. Private endpoint or VNet integration later. |
| Agents and platform services share a node pool | Same nodes, separate namespaces. No node-level separation until the `agents` pool exists. |
| No egress filtering | Agents can reach any destination. Firewall subnet is reserved. |
| `-target` for staged applies | Terraform warns against routine use. Final untargeted plan should show no changes. |
| ACR on public endpoint | Basic SKU has no network rules; private endpoints need Premium. |
| Storage LRS, Postgres Burstable, no HA | Cost. |

## Open

- **Argo artifact repository vs. ADR-003.** Argo's `wait` container in each step pod saves output artifacts and logs; the `init` container fetches inputs ([architecture](https://argo-workflows.readthedocs.io/en/latest/architecture/)). For agent steps that is the agent pod's identity, and agent pods get no cloud identity. As built, only the Argo controller and server can reach the `argo` account, so agent steps cannot write Argo artifacts or archived logs. Options: workload identity on agent ServiceAccounts scoped to the `argo` container (contradicts ADR-003), an account key in a Secret in `agents` (shared keys are disabled), or no Argo artifacts from agent steps. Undecided.

## Not carried over from cloudkube

Inherited patterns dropped, with reason:

| Pattern | Why dropped |
|---|---|
| Separate repos per lifecycle | Single root with modules, per this repo's brief. |
| `provider` blocks inside modules | Modules declare `required_providers` only. |
| Kubelet VM Contributor / Managed Identity Operator on resource groups | Not needed; control plane gets Managed Identity Operator on the kubelet identity only. |
| Vnet-integrated API server subnet | Default public endpoint chosen. |
| NGINX ingress, TLS certs, DNS zone | Out of scope. |
| Node SSH key (`linux_profile`) | Not needed. |
