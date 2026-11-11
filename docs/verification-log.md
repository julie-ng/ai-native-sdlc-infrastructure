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
