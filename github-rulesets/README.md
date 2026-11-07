# GitHub Rulesets

A minimal ruleset to use as inspiration: give agents freedom to work on their own branches while still protecting production environments, in my case via the `main` branch.

### Give agents own branches

Ruleset denies creation and deletion of all branches, _except_:

- `agents/**/*`
- `claude/**/*`
- `codex/**/*`

### `main` branch protections

_N.B. I've configured bypass for admins, i.e. me._

- Requires signed commits
- Requires pull requests
- Disallow…
  - update (also prevents agents merging PRs targeting `main`)
  - delete 
  - create
- Block force pushes

### References

- [GitHub Docs: Managing rulesets for a repository](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/managing-rulesets-for-a-repository)
