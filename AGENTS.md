# AGENTS.md

Project-specific instructions for any agent working in this repo, alongside the shared instructions below.

> [!NOTE]
> Harness-agnostic by design. A `CLAUDE.md` stub, if present, imports this file via `@AGENTS.md`; only harness-specific additions belong there.

## About this repo

- Terraform for the AI SDLC platform on Azure: one AKS cluster plus its backing services. Single environment (`dev`).
- Infrastructure choices and trade-offs: [`docs/decisions-log.md`](./docs/decisions-log.md). Read it before changing anything.

## Reading order

1. [README](./README.md): modules, apply order, manual steps, unverified items
2. [`docs/decisions-log.md`](./docs/decisions-log.md)
3. The ADRs relevant to the task
4. Open issues on this repo, for deferred target designs

If an ADR and this repo disagree, flag it to the human developer. Don't silently pick one.

## Agents write, humans apply

- **Agents have no Azure access.** Terraform is written blind.
- Never run `terraform plan`, `apply`, `import`, `state` or `destroy` against Azure, and never `kubectl` against the cluster. The human developer runs these manually, one module at a time.
- Before handing back, run `make lint`: `terraform fmt -check`, `terraform validate`, `tflint --recursive`. All three must pass.
- Report what was checked offline and what wasn't. Anything only an apply can prove goes into the README's **Unverified** list.

## Verify, don't guess

- **Provider argument names:** check them against `terraform providers schema -json` for the pinned version, not against memory or older examples. azurerm 5.x renamed many arguments and added required blocks.
- **Azure and Kubernetes behaviour:** primary sources only (Microsoft Learn, provider source and docs at the pinned tag, upstream project source). Link the source in `docs/decisions-log.md`.
- When the provider docs contradict each other, read the provider source at the pinned tag and cite the file.

## Security rules

- **No secrets in Terraform.** Nothing that puts a credential into state: no `azurerm_key_vault_secret` values, no generated passwords, no Kubernetes token Secrets. Document them as manual steps in the README instead.
- **No hard-coded user, tenant or subscription IDs.** The deployer comes from `data.azurerm_client_config.current`, and the subscription from `az account set`.
- **Entra ID over keys.** Shared keys stay off on storage. Postgres is Entra-only. ACR admin user stays off.
- **Agent pods get no cloud identity except approved secret reads (ADR-003, #18, #26).** `coder` and `planner` each have a dedicated identity with `Key Vault Secrets User`, assigned separately on each secret they need: `coder` reads the signing key, GitHub PAT and AI gateway key; `planner` reads the PAT and gateway key. `reviewer`, `open-pr` and `argo-executor` have no identity. Any further agent cloud access needs an explicit decision from the human developer.
- **Least privilege per identity.** Scope role assignments to the narrowest resource, e.g. a container rather than its account. Don't share an identity between components with different access needs.
- **Only GitHub Actions pushes to ACR.** `AcrPush` goes only to the two GitHub OIDC identities, each federated to the `production` environment of one repo (`ai-native-sdlc-agent-images`, `ai-native-sdlc-platform-services`). Nothing in the cluster gets push.
- **Config is not a boundary.** Network rules, firewall rules and RBAC are mitigations. Name what they actually enforce.

## Terraform conventions

- One root module calls `modules/networking`, `modules/shared`, `modules/identities`, `modules/cluster`, `modules/kubernetes` and `modules/platform_stop_mi`, applied in that order with `-target`. Dependencies flow through module outputs; add `depends_on` only where Terraform can't see the dependency.
- Modules declare `required_providers` with version ranges, and contain no `provider` blocks.
- **Naming:** `{name}-{type}` for resource groups, with no random suffix (including `{name}-cluster-rg` and `{name}-aks-managed-rg`). Add `-{suffix}` for the AKS cluster resource name and for globally unique names. Hyphen-less names are squashed: `aisdlc{suffix}cr`.
- Files split by concern (`_aks.tf`, `_rbac.tf`, `_identities.tf`), with `# ====` banner comments.
- Defaults go in `defaults.auto.tfvars`. Personal values (admin IPs) go in git-ignored `private.auto.tfvars`.
- `prevent_destroy` on anything that outlives a cluster rebuild: static IPs, databases.
- **When to use a variable:**
  - Don't add variables for things that don't vary. Hard-code them with a comment.
  - **Exception: values this repo chooses, and values that matter to the security model, are always variables**, even if they never change. Examples: namespace names, the IMDS address. Reviews and audits scan `main.tf`, `variables.tf` and `defaults.auto.tfvars`, so these must be visible there, not buried inline in a module. If a value isn't ours to change, say so in its description.

## Decisions

- Every infrastructure choice gets a row in [`docs/decisions-log.md`](./docs/decisions-log.md), with the date, the decision and why. That includes small choices and choices made by the human developer.
- Deferred target designs go into a GitHub issue, linked from the decision row.

## Writing style

- Bullets over prose for three or more items.
- Comments in `.tf` files explain *why*, not what.

## Commit attribution and delivery

- Codex commits include `Co-Authored-By: Codex <version> <model> <codex@users.noreply.github.com>`, for example `Co-Authored-By: Codex 6.1 Sol <codex@users.noreply.github.com>`. Keep the configured agent as commit author. Other model co-author trailers must include model name and version.
- Never rewrite another contributor's work without asking. Open a PR for review-ready changes; the human developer reviews and merges.

## Shared instructions

Read and follow these alongside this repo’s project-specific instructions. Explicit project-specific exceptions override shared defaults; otherwise both apply.

- [Working practices](./.agents/shared/working-practices.md)
- [Communication and writing](./.agents/shared/communication.md)
- [Cross-session memory](./.agents/shared/memory.md)
- [Git & GitHub workflow](./.agents/shared/github-workflow.md)
