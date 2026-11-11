# Verification log

Checks completed by the human developer. Open checks stay in the README's [Unverified](../README.md#unverified) list; move them here once done. The agent ran no Azure or cluster commands for any of these.

Provisioning of all infrastructure modules was confirmed on 2026-10-22: networking, shared services (including PostgreSQL 17/B1ms in North Europe), identities and role assignments, all three AKS pools, and the Kubernetes module. The custom resource groups and staged applies were accepted.

## Platform lifecycle

- [x] `make stop-cluster` completes successfully.
- [x] Final untargeted `make plan` shows no pending changes after all stages.
- [x] `make start-cluster`, node readiness, and `make kubecontext` after restart.
- [x] Platform/database start and stop using configured resource names.
- [x] `platform_stop_mi` module: identities-group lookup, identity/federation creation, built-in role assignments and first manual stop workflow.

## Credentials and secrets

- [x] `local-dev` service principal: Entra app registration created by the applying identity, credential created with `make local-dev-credential`, and user delegation SAS URLs generated with it against the `artifacts` account.
- [x] `make reset-sdlc-secrets`: run and the resulting values checked in Azure Portal on 2026-11-05; `token-broker-gh-app-private-key` remained unchanged. Temporary GPG isolation/cleanup and key properties were checked offline with mocked uploads.
- [x] #19 identity replacement: plan reviewed and applied on 2026-11-05. `workflow-service-mi` and `artifact-service-mi` were replaced by `platform-services-mi`, `token-broker-mi` by `gh-token-broker-mi`, and `foreman-mi` was added. Workload-identity `prevent_destroy` was restored afterwards.
- [x] `platform-services-mi` database grants on `workflow` applied on 2026-11-10; `has_database_privilege('platform-services-mi', 'workflow', 'CREATE')` returns `t` ([#31](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/31)).

## Initial release (2026-11-10 to 2026-11-11)

End to end on 2026-11-11: workflow `initial-release-gxqw4` (`foreman → planner → coder`) opened a signed PR on the test repository, shown as **Verified** on GitHub. The checks below are what that run and the preceding tests proved for this repo.

- [x] #26 grants: `planner-mi` has exactly two secret-scoped `Key Vault Secrets User` grants (2026-11-10), `coder-mi` exactly three (2026-11-11), listed with `az role assignment list`.
- [x] #26 CSI: a labeled `planner` pod mounts `planner-secrets` with nonempty files, values not printed (2026-11-10). A `planner` pod using `coder-secrets` fails to mount at authentication (401): `coder-mi` has no federation for `agents:planner`.
- [x] #26 and #18 coder: the coder pod mounts `coder-secrets`; the mounted PAT pushes and the mounted GPG key signs commits that GitHub shows as **Verified** (2026-11-11). With only its three grants, `coder-mi` cannot read the admin/HMAC or GitHub App secrets.
- [x] `foreman` (workflow `foreman-dll9r`, 2026-11-11): the CSI admin-token mount works, the run is created, and both HMAC Secrets are created with the Workflow as owner (UID matched). After the Workflow TTL, the Workflow and both Secrets return `NotFound`.
- [x] Executor-only tokens: in the `foreman` pod, `exec-sa-token` is mounted only in `init` and `wait`, and the Azure identity token only in `main` (`azure.workload.identity/skip-containers: init;wait`). Argo mirrors `main` mounts into `wait` under `/mainctrfs`; the workflow templates delete the credential copies.
- [x] `platform-services-mi` (2026-11-10): authenticates to PostgreSQL with an Entra token and runs its startup migrations; signs user delegation SAS URLs for Blob upload and download, tested from a pod in `agents`.
- [x] #29: the `platform-services` pod in `platform` mounts both files from `platform-services-secrets`. `POST /api/runs` with the Key Vault admin token returned 201 and issued HMAC step tokens, so both files loaded.
- [x] Agent workflows and application integrations: platform services, Blob Storage, the AI gateway and GitHub all worked from the cluster in `initial-release-gxqw4`. No secrets were found in its logs.

## Argo Workflows (2026-11-05)

- [x] Applied the four controller RBAC resources, installed chart 2.0.16 / Argo v4.1.6, and created the executor token Secret. Workflow `hello-world-7xzjr` succeeded in `agents` as `planner` (1/1 step, 20 seconds), confirming executor result reporting under `deny-imds`.
- [x] Hello-world ran on `aks-agents-39765645-vmss000008`, controller on `aks-platform-20300205-vmss000009` (Running, 0 restarts); a repeat `make install-argo` succeeded (release revision 2).

## Agent pod restrictions (#4, 2026-10-25)

[Details](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/4#issuecomment-6394927018). The deployed cluster was switched to Cilium in place on 2026-10-24; the apply reimaged all pools (about 9 minutes).

- [x] `make plan-cluster` showed an in-place update, not a replace. Cilium runs on every node; no kube-proxy pods.
- [x] From a pod in `agents`, IMDS instance metadata and token requests time out (`curl -s -H Metadata:true --connect-timeout 10 "http://169.254.169.254/metadata/instance?api-version=2023-11-15"`).
- [x] Control: the same request from a pod in `default` returns metadata, so the policy is what blocks `agents`.
- [x] From the `agents` pod, `curl https://github.com` returns `200`, `getent hosts kubernetes.default.svc.cluster.local` resolves, and the API server answers `401`.
- [x] A pod with `hostNetwork: true` in `agents` is rejected: `violates PodSecurity "baseline:latest"`.
- [x] `kubectl get netpol deny-imds -n agents -o yaml` shows `namespaceSelector: {}`.
- [x] Container Insights still collects after the switch: `KubePodInventory` shows the test pod in `agents`.
- [x] Node identities: all pools carry the kubelet identity (`AcrPull` on the registry only) and the Key Vault CSI add-on identity (no role assignments). No Container Insights identity is attached.
- [x] [WireServer](https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16) (`168.63.129.16`) times out from `agents` pods on ports 80 and 32526. `deny-imds` doesn't cause this, and this repo doesn't enforce it.
