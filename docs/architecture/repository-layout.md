---
type: Architecture Concept
title: Repository Layout
description: Stable map of the repository's main source directories.
when: Read when locating repository code or deciding where a new file belongs.
resource: README.md
tags: [architecture, layout]
---

# Repository Layout

The repository is a feature-first, multi-host Den fleet. Entity declarations
describe topology separately from host implementations, while reusable
capabilities are composed as aspects.

| Path | Purpose |
| --- | --- |
| `flake.nix` | Generated flake; regenerate with `nix run .#write-flake`. |
| `modules/defaults.nix` | Repo-wide `den.default` and shared host composition. |
| `modules/entities.nix` | Fleet topology: hosts, users, and user aspect attachments. |
| `modules/hosts/` | Host aspects. |
| `modules/aspects/` | Reusable den aspects. |
| `modules/_services/` | NixOS service modules imported by service aspects. |
| `modules/_packages/` | Local and service-only packages. |
| `modules/checks.nix` | Flake checks. |
| `modules/git-hooks.nix` | Development shell and pre-commit hooks. |
| `docs/` | Architecture, host, service, runbook, research, and agent docs. |
| `secrets/` | Consumer-scoped encrypted `sops-nix` secrets. |

## Related

- [Den aspect composition](den-aspect-composition.md)
- [Service model](../services/service-model.md)
