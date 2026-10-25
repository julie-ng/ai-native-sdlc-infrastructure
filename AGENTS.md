# AGENTS.md

Rules for any agent working in this repo, regardless of harness or model. This file is the single source of truth for repository instructions.

> [!NOTE]
> Harness-agnostic by design. A `CLAUDE.md` stub, if present, imports this file via `@AGENTS.md`; only harness-specific additions belong there.

## About this repo

- Terraform for the AI SDLC platform on Azure: one AKS cluster plus its backing services. Single environment (`dev`).
- Design lives in the parent repo, [julie-ng/ai-native-sdlc](https://github.com/julie-ng/ai-native-sdlc): [architecture](https://github.com/julie-ng/ai-native-sdlc/tree/main/architecture) and [ADRs](https://github.com/julie-ng/ai-native-sdlc/tree/main/architecture/decisions). This repo implements them; it does not redefine them.
- Infrastructure choices and trade-offs: [`docs/decisions.md`](./docs/decisions.md). Read it before changing anything.

## Reading order

1. [README](./README.md): modules, apply order, manual steps, unverified items
2. [`docs/decisions.md`](./docs/decisions.md)
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
- **Azure and Kubernetes behaviour:** primary sources only (Microsoft Learn, provider source and docs at the pinned tag, upstream project source). Link the source in `docs/decisions.md`.
- When the provider docs contradict each other, read the provider source at the pinned tag and cite the file.
- Mark unverified claims **in the file**, not just in chat.

## Security rules

- **No secrets in Terraform.** Nothing that puts a credential into state: no `azurerm_key_vault_secret` values, no generated passwords, no Kubernetes token Secrets. Document them as manual steps in the README instead.
- **No hard-coded user, tenant or subscription IDs.** The deployer comes from `data.azurerm_client_config.current`, and the subscription from `az account set`.
- **Entra ID over keys.** Shared keys stay off on storage. Postgres is Entra-only. ACR admin user stays off.
- **Agent pods get no cloud identity (ADR-003).** Workload identities are for platform services only. Any change that gives an agent ServiceAccount Azure access needs an explicit decision from the human developer.
- **Least privilege per identity.** Scope role assignments to the narrowest resource, e.g. a container rather than its account. Don't share an identity between components with different access needs.
- **Nothing pushes to ACR.** Images are pushed manually. No identity in this repo, the cluster or GitHub gets push.
- **Config is not a boundary.** Network rules, firewall rules and RBAC are mitigations. Name what they actually enforce.

## Terraform conventions

- One root module calls `modules/networking`, `modules/shared`, `modules/identities`, `modules/cluster` and `modules/kubernetes`, applied in that order with `-target`. Dependencies flow through module outputs; add `depends_on` only where Terraform can't see the dependency.
- Modules declare `required_providers` with version ranges, and contain no `provider` blocks.
- **Naming:** `{name}-{type}` for resource groups, with no random suffix (including `{name}-cluster-rg` and `{name}-aks-managed-rg`). Add `-{suffix}` for the AKS cluster resource name and for globally unique names. Hyphen-less names are squashed: `aisdlc{suffix}cr`.
- Files split by concern (`_aks.tf`, `_rbac.tf`, `_identities.tf`), with `# ====` banner comments.
- Defaults go in `defaults.auto.tfvars`. Personal values (admin IPs) go in git-ignored `private.auto.tfvars`.
- `prevent_destroy` on anything that outlives a cluster rebuild: static IPs, databases.
- **When to use a variable:**
  - Don't add variables for things that don't vary. Hard-code them with a comment.
  - **Exception: values this repo chooses, and values that matter to the security model, are always variables**, even if they never change. Examples: namespace names, the IMDS address. Reviews and audits scan `main.tf`, `variables.tf` and `defaults.auto.tfvars`, so these must be visible there, not buried inline in a module. If a value isn't ours to change, say so in its description.

## Decisions

- Every infrastructure choice gets a row in [`docs/decisions.md`](./docs/decisions.md), with the date, the decision and why. That includes small choices and choices made by the human developer.
- Write trade-offs down even once decided.
- Deferred target designs go into a GitHub issue, linked from the decision row.
- **Don't carry forward unevaluated choices.** Patterns inherited from earlier repos are flagged as inherited, not presented as settled.

## Writing style

- Succinct, load-bearing only. Bullets over prose for three or more items.
- Comments in `.tf` files explain *why*, not what.
- Link out instead of restating external docs.
- No hard line breaks mid-paragraph.

## Git & GitHub

- Use the configured agent identity, never the human developer's identity.
- In a dev container, load the agent environment file mounted read-only by the hosting checkout's `devcontainer.json` and follow its instructions. Don't add mount paths to documentation.
- Set repository-local `user.name` / `user.email` from `GIT_USER_NAME` / `GIT_USER_EMAIL`, import the provided agent GPG key, set `user.signingkey` and `commit.gpgsign=true`, and sign all commits. In a worktree, use `git config --worktree`.
- Authenticate as `GITHUB_USERNAME` using `GITHUB_PAT`. For `gh`, export `GH_TOKEN="$GITHUB_PAT"`; use `gh auth setup-git` for HTTPS.
- Codex commits include `Co-Authored-By: Codex <version> <model> <codex@users.noreply.github.com>`, for example `Co-Authored-By: Codex 6.1 Sol <codex@users.noreply.github.com>`. Keep the configured agent as commit author. Other model co-author trailers must include model name and version.
- Never copy credential values into documentation, commits, issues or PRs.

## Changes

### Security

- Never edit or commit directly on `main`, push to it or merge into it.
- GitHub collaborator permissions, repository rulesets and push rules restrict the agent's access. Work on branches prefixed with `agent/`. These controls do not authorize changes to protected branches or bypassing their protections.
- Creating task branches/worktrees is authorized. In the configured dev container, signed commits and normal pushes of task changes to the agent's own branch are authorized. Session-specific instructions about pushing take precedence.
- Amends, squashes, force pushes and rewriting published history of the agent's own non-protected task branches are allowed and encouraged to keep a clean history. Ask before deleting any branch or rewriting another contributor's work.

**Sandbox escalation is pre-authorized for the Git operations allowed above**; use the harness approval mechanism without asking the human developer to repeat that authorization. Repository instructions do not override harness restrictions.

### Guidance

- Fetch the remote default branch before creating a task branch or worktree. Create independent `agent/` task branches from that fetched branch, not the current checkout or another task branch.
- Target PRs at the repository's default branch. Only stack branches/PRs when explicitly requested; state the dependency first. After a prerequisite PR merges, retarget dependent PRs and verify their state before branch cleanup.
- Use a separate worktree when another agent is working in the repository. Don't modify another agent's checkout or task branch; establish ownership before concurrent writes.
- Request harness escalation for authorized operations blocked by the sandbox.
- Commit coherent completed changes at meaningful checkpoints, before handoff or switching tasks. Use small, atomic, signed Conventional Commits (`type(scope): description`).
- Push at review-ready milestones or handoff when authorized and open a PR. The human developer reviews and merges. Report whether work is uncommitted, committed locally or pushed.

## Communication

- Lead with the correction or the result. Report failures with the actual output.
- Say explicitly what was left out, and why.
- Flag adjacent problems; don't fix them unasked.
