---
type: Knowledge Bundle
title: Nix Repo Knowledge
description: Entry point for the repo's OKF-style architecture, operations, and decision knowledge.
resource: README.md
tags: [nix, nixos, home-manager, den]
---

# Nix Repo Knowledge

This bundle records stable knowledge about the NixOS and Home Manager
configuration in this repository. It is intentionally close to the codebase:
concept files explain intent and link back to source files instead of copying
module contents.

## Architecture

- [Den aspect composition](architecture/den-aspect-composition.md)
- [Repository layout](architecture/repository-layout.md)
- [Secrets management](architecture/secrets-management.md)

## Hosts

- [Alpha](hosts/alpha.md)
- [Beta](hosts/beta.md)

## Services

- [Service model](services/service-model.md)

## Runbooks

- [Failed auto-upgrade rollback](runbooks/failed-auto-upgrade-rollback.md)
- [Restore service backups](runbooks/restore-service-backups.md)
- [Check native container DNS](runbooks/check-native-container-dns.md)

## Decisions

- [Keep knowledge in this repo](decisions/keep-knowledge-in-repo.md)
