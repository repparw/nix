---
type: Architecture Decision
title: Keep Knowledge In This Repo
description: Store repo-specific operational and architecture knowledge beside the Nix configuration.
resource: docs/index.md
tags: [decision, docs, knowledge]
---

# Keep Knowledge In This Repo

Repository knowledge lives under `docs/` because it describes this exact Nix
configuration. Versioning the knowledge with the code makes configuration
changes and documentation changes reviewable together.

A separate knowledge repository would be useful only if the same docs needed
to aggregate several repositories, publish a sanitized public view, or serve
multiple unrelated projects from one central location.

## Consequences

- Documentation should link to source modules instead of duplicating config.
- README stays short and points to the documentation index.
