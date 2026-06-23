---
type: Architecture Concept
title: Secrets Management
description: Repo convention for encrypted secrets and secret references.
resource: modules/aspects/secrets.nix
tags: [security, secrets, sops-nix]
---

# Secrets Management

Do not put plaintext secrets in this repository. Secret material belongs in
`secrets.yaml` and is managed through `sops-nix`.

Docs, plans, commits, and knowledge files should refer to SOPS secret names or
source modules only. They should not copy secret values out of `secrets.yaml`.

## Source

- `modules/aspects/secrets.nix`
- `secrets.yaml`

## Related

- [Repository layout](repository-layout.md)
