---
type: Documentation Index
title: Nix Repository Documentation
description: Entry point for the repository's architecture, operations, and decision documentation.
when: Start here when selecting repository documentation for a task.
resource: README.md
tags: [nix, nixos, home-manager, den]
---

# Nix Repository Documentation

These pages record stable knowledge about the configuration and link to source
files instead of copying module contents.

## Architecture

- [Den aspect composition](architecture/den-aspect-composition.md)
- [Ingress policy](architecture/ingress-policy.md)
- [Repository layout](architecture/repository-layout.md)
- [Secret inventory and management](architecture/secret-inventory.md)

## Hosts

- [Host profiles](hosts.md)

## Services

- [Service model](services/service-model.md)
- [Hermes configuration and operations (private)](https://github.com/repparw/hermes-config)

## Runbooks

- [Diagnose fleet observability](runbooks/monitoring.md)
- [Configure Grafana Cloud](runbooks/grafana-cloud.md)
- [Check native container DNS](runbooks/check-native-container-dns.md)
- [Update rollback](runbooks/update-rollback.md)
- [Fleet health, backups, and deployment](runbooks/fleet-operations.md)
- [Hermes crash triage](runbooks/hermes-crash-triage.md)
- [Restore service backups](runbooks/restore-service-backups.md)
- [Restore host state from offsite backups](runbooks/host-recovery.md)
- [Change host persistence](runbooks/host-persistence.md)
- [Moonlight TV 200 Mbps bitrate build](runbooks/moonlight-tv-bitrate.md)

## Fixes

- [Tweaks](tweaks.md)
- [Troubleshooting](troubleshooting.md)

## Research

- [Multi-room audio hardware](research/multi-room-audio-hw.md)
- [Multi-room audio Music Assistant setup](research/multi-room-audio-music-assistant-setup.md)

## Agent guidance

- [Verify NixOS configuration changes](../.agents/skills/verify-fleet-change/SKILL.md)
- [Operate the running fleet](../.agents/skills/fleet-operations/SKILL.md)
- [Watch for an upstream fix](../.agents/skills/watch-upstream/SKILL.md)
- [Manage page watchers](../.agents/skills/manage-page-watchers/SKILL.md)
- [Domain docs](agents/domain.md)
- [GitHub issue tracker](agents/issue-tracker.md)
- [Triage labels](agents/triage-labels.md)
