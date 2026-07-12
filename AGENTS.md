Repo follows upstream `vic/den` default-template structure.

## Core Rules
- Configure generated aspects through `den.aspects.<name>`.
- Use `includes` for aspect composition.
- Use `imports` only for real Nix module imports.
- Put repo-wide defaults in `modules/defaults.nix` via `den.default`.

- Keep related logic together, usually wrapped in the same aspect.
- Put reusable features in dedicated aspect files.

- Do not put plaintext secrets in repo; use `sops-nix`.

## Spoken Communication

Agents can speak to the user via TTS with `say "message"`.

## Nix Research

Use `mcp-nixos` before guessing package attributes, option paths, Nix functions, package versions, or documentation. It covers NixOS packages and options, Home Manager, nix-darwin, Nixvim, Noogle, FlakeHub, NixOS Wiki, `nix.dev`, package history, binary-cache status, and pinned flake inputs.

Use `nh search` for repository-local CLI research and GitHub-backed Nixpkgs development history:

```console
nh search prs <query>
nh search issues <query>
```

Check issues before implementing a local workaround. For merged pull requests, verify that the change reached the Nixpkgs branch pinned by this flake.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

The tracker uses the five default triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

This repository uses a single-context domain-doc layout. See `docs/agents/domain.md`.
