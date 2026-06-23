---
type: Architecture Concept
title: Repository Layout
description: Stable map of the repository's main source directories.
resource: README.md
tags: [architecture, layout]
---

# Repository Layout

This repository follows the upstream `vic/den` default-template structure.

- `flake.nix` is generated through `flake-file`. Do not edit it directly.
- `modules/defaults.nix` defines repo-wide `den.default` behavior and shared
  host composition.
- `modules/hosts/` contains host aspects.
- `modules/aspects/` contains reusable den aspects.
- `modules/_services/` contains NixOS service modules imported by the service
  aspect.
- `modules/_packages/` contains local package definitions and service-only
  packages.
- `modules/checks.nix` defines flake checks.
- `modules/git-hooks.nix` defines the development shell and pre-commit hooks.
- `knowledge/` contains this OKF-style knowledge bundle.

## Related

- [Den aspect composition](den-aspect-composition.md)
- [Service model](../services/service-model.md)
