# Workload integration

What workloads maintained in other repos (workflow templates, platform-services, agent images) must do to use the identities, ServiceAccounts and secret mounts this repo creates. For who can read what, see the [identity diagrams in the README](../README.md#identity-and-access-model-iam).

Key Vault values were populated under #21. Don't rerun initialization or reset for these changes. Terraform only configures names, grants and CSI references.

## Scheduling

- Platform services select `kubernetes.azure.com/agentpool: platform`.
- Agent pods select `kubernetes.azure.com/agentpool: agents` and tolerate `workload=agents:NoSchedule`.
- These settings don't isolate anything for security.

## Trusted foreman step (#19)

- `foreman-mi` reads only `platform-services-admin-token`. Names are in `key_vault_secret_names` in `defaults.auto.tfvars`.
- The workflows repo must run the trusted step as `foreman` in `agents`, label its pod `azure.workload.identity/use: "true"`, and mount the read-only CSI volume using SecretProviderClass `foreman-admin-token` (root variable `foreman_secret_provider_class_name`) into the main container only. No admin-token Kubernetes Secret synchronization is configured.
- The trusted main container needs its Kubernetes API ServiceAccount token to create the per-step Secrets; it is separate from the Azure federation token and the Argo executor token. If the template disables automount, it must explicitly project the API token for this container. Keep the executor's existing permissions separate.
- Create each HMAC Secret with a same-namespace Workflow ownerReference using `{{workflow.name}}` and `{{workflow.uid}}`, and `blockOwnerDeletion: false`. No Workflow-read or finalizer permissions are needed. The Role grants only `secrets: create`; it permits any Secret name in `agents`, accepted because this step is trusted. The agent steps mount only their own HMAC Secret; tokens never go through Argo parameters.
- `deny-imds` stays unchanged. CSI workload identity does not need workload-pod IMDS access. This policy permits other egress; adding a narrower allow policy would not restrict it because NetworkPolicies are additive.

## Planner and coder secret mounts (#18, #26)

| ServiceAccount / identity | SecretProviderClass | Mounted file names |
|---|---|---|
| `coder` / `coder-mi` | `coder-secrets` | `agent-gpg-private-key`, `julieio-goose-github-pat`, `vercel-ai-gateway-api-key` |
| `planner` / `planner-mi` | `planner-secrets` | `julieio-goose-github-pat`, `vercel-ai-gateway-api-key` |

- Root `agent_secret_provider_class_names` selects the two roles and their class names; `key_vault_secret_names` supplies object/file names.
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

- Files appear under `/mnt/agent-secrets/<object-name>`. The agent entrypoint maps the PAT to `GH_TOKEN` and the gateway key to `AI_GATEWAY_API_KEY`; coder imports the private key into its private GPG home. Do not print values or pass them through Argo parameters. No Kubernetes Secret synchronization is configured.
- The PAT is deliberately shared with planner: it can push within its token permissions. Main-branch rulesets still require a PR and signed commits; they do not make planner read-only. The token broker is the deferred replacement ([#26](https://github.com/julie-ng/ai-native-sdlc-infrastructure/issues/26)).
- CSI uses workload identity; the node CSI add-on identity gets no grant. Per-run HMAC tokens remain with foreman.

> [!IMPORTANT]
> **ADR discrepancy:** [ADR-003](https://github.com/julie-ng/ai-native-sdlc/blob/main/architecture/decisions/003-platform-services-vs-agent-pods.md) still limits the exception to the signing key. The human decision in #26 (2026-11-07) supersedes that limit for these long-lived secrets; the parent ADR update is pending.

## Platform services (#29)

- Run as ServiceAccount `platform-services` in `platform`.
- SecretProviderClass `platform-services-secrets` uses `platform-services-mi`. Mount it read-only at `/mnt/secrets` to read `platform-services-admin-token` and `platform-services-hmac-key`. No Kubernetes Secret synchronization is configured.
- The Deployment, workload-identity pod label and volume mount live in [platform-services](https://github.com/julie-ng/ai-native-sdlc-platform-services/issues/45).

## GitHub token broker

- Runs as ServiceAccount `token-broker` in `github-broker`, annotated for `gh-token-broker-mi`.
- SecretProviderClass `github-broker-secrets` (root variable `github_broker_secret_provider_class_name`) mounts the single file `token-broker-gh-app-private-key`. The broker Deployment must set the workload-identity pod label and mount this CSI volume read-only; no Kubernetes Secret synchronization is configured.
- Its Kubernetes API token needs permission to create TokenReviews and get pods in `agents`; Terraform grants only those two permissions. The Deployment and Service remain in the broker repository.
- Its repository's `production` GitHub environment uses the client ID from `github_workflows.github_broker.client_id` for OIDC image pushes. The federated subject is `repo:julie-ng@1269507/ai-native-sdlc-github-broker@1433193704:environment:production`; matching the emitted subject and a successful push remain unverified until the human-run workflow.
