---
type: Documentation Index
title: Nix Repository Documentation
description: Entry point for the repository's architecture, operations, and decision documentation.
resource: README.md
tags: [nix, nixos, home-manager, den]
---

# Nix Repository Documentation

These docs record stable knowledge about the NixOS and Home Manager
configuration in this repository. They stay intentionally close to the codebase:
concept files explain intent and link back to source files instead of copying
module contents.

## Architecture

- [Den aspect composition](architecture/den-aspect-composition.md)
- [Repository layout](architecture/repository-layout.md)
- [Secret inventory](architecture/secret-inventory.md)
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

## Architecture decisions

- [Keep knowledge in this repo](adr/keep-knowledge-in-repo.md)
