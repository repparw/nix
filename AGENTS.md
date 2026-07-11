Repo follows upstream `vic/den` default-template structure.

## Core Rules
- Configure generated aspects through `den.aspects.<name>`.
- Use `includes` for aspect composition.
- Use `imports` only for real Nix module imports.
- Put repo-wide defaults in `modules/defaults.nix` via `den.default`.

- Keep related logic together, usually wrapped in the same aspect.
- Put reusable features in dedicated aspect files.

- Do not put plaintext secrets in repo; use `sops-nix`.

## Nix Research with `nh search`

Use `nh search` before guessing package names, option paths, or whether an upstream Nixpkgs fix has landed.

### Packages

```console
nh search packages <query>
```

Use this to find package attribute names and package metadata. `nh search <query>` currently defaults to package search, but prefer the explicit `packages` subcommand in documentation and automated workflows.

### NixOS and Home Manager options

```console
nh search options <query>
```

Use this before adding or changing module options. The old `nh search --options <query>` syntax was removed in nh 4.4.0.

Search both the full option path and relevant descriptive terms when the first query is inconclusive.

### Nixpkgs pull requests

```console
nh search prs <query>
nh search prs 123456
nh search prs '#123456'
```

Use this to investigate recent upstream implementations, regressions, package updates, and fixes. For merged pull requests, check the reported Nixpkgs branches to determine whether the change has reached the branch used by this flake.

Numeric and `#<number>` queries fetch that pull request directly.

GitHub authentication is read in this order:

1. `GH_TOKEN`
2. `$XDG_STATE_HOME/nh/github-token`
3. `~/.local/state/nh/github-token`

Never commit the token.

### Nixpkgs issues

```console
nh search issues <query>
```

Use this to find current Nixpkgs bug reports and discussions without pull-request results. Search issues before implementing a local workaround for behavior that may already be known upstream.

### Offline package search

```console
nh search offline -D <database-directory> <query>
```

Alternatively, set `NH_OFFLINE_DB` to the spam-db database directory. Use offline search when network access is unavailable or reproducible local search is preferable.

### Machine-readable output

```console
nh search --json packages <query>
nh search --json options <query>
nh search --json prs <query>
nh search --json issues <query>
```

Use `--json` when results will be parsed or compared programmatically. Do not parse human-formatted output when JSON is available.

### Default search mode

```console
nh search --default-search packages <query>
nh search --default-search options <query>
```

When no subcommand is supplied, `--default-search` selects either `packages` or `options`. Prefer explicit subcommands in repository instructions and scripts so behavior is immediately visible.
