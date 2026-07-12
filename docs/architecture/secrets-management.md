---
type: Architecture Concept
title: Secrets Management
description: Repo convention for encrypted, host-deployable secrets and secret references.
resource: modules/aspects/secrets.nix
tags: [security, secrets, sops-nix]
---

# Secrets Management

Do not put plaintext secrets in this repository. Secret material belongs in
consumer-scoped files under `secrets/` and is managed through `sops-nix`.

Each service or aspect declares its own `sopsFile`. This limits the ciphertext
and recipient blast radius and makes secret ownership visible next to the
consumer. NixOS decrypts with the machine SSH host key at
`/etc/ssh/ssh_host_ed25519_key`; the personal Age recipient in `.sops.yaml` is
recovery access and is not used during activation.

Docs, plans, and commits should refer to SOPS secret names or source modules
only. They should not copy secret values out of `secrets/`.

## Source

- `modules/aspects/secrets.nix`
- `secrets/`
- [Secret inventory](secret-inventory.md)

## Related

- [Repository layout](repository-layout.md)
