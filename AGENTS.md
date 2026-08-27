Repo follows upstream `vic/den` default-template structure.
- Configure generated aspects through `den.aspects.<name>`.
- Use `includes` for aspect composition.
- Use `imports` only for real Nix module imports.
- Put repo-wide defaults in `modules/defaults.nix` via `den.default`.

- Keep related logic together, usually wrapped in the same aspect.
- Put reusable features in dedicated aspect files.

- Do not put plaintext secrets in repo; use `sops-nix`.

Use `nh search` for packages, options, issues and PRs on nixpkgs/home-assistant

Check issues before implementing a local workaround. For merged pull requests, verify that the change reached the Nixpkgs branch pinned by this flake.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

The tracker uses the five default triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

This repository uses a single-context domain-doc layout. See `docs/agents/domain.md`.

### Documentation routing

For task-specific context, start at `docs/index.md`. Inspect each candidate
page's YAML frontmatter and use its `when`, `type`, `tags`, and `resource` fields
to select relevant documentation before reading full pages. Do not read every
doc by default; follow matching pages' source and related links as needed.
