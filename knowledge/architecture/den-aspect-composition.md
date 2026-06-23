---
type: Architecture Concept
title: Den Aspect Composition
description: Rules for composing repo behavior with den aspects.
resource: modules/defaults.nix
tags: [architecture, den, aspects]
---

# Den Aspect Composition

Generated aspects are configured through `den.aspects.<name>`.

Use `includes` for aspect composition. Use `imports` only for real Nix module
imports. Repo-wide defaults belong in `modules/defaults.nix` under
`den.default`.

Keep related logic together, usually wrapped in the same aspect. Reusable
features should live in dedicated aspect files.

## Source

- `modules/defaults.nix`
- `modules/aspects/`
- `modules/hosts/`

## Related

- [Repository layout](repository-layout.md)
