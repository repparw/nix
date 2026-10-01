---
type: Runbook
title: Migrate Home Assistant Custom Components
description: Move existing mutable component directories before switching selected integrations to Nix packages.
when: Read before activating Nix-packaged Home Assistant custom components on pi.
resource: modules/aspects/services/homeassistant.nix
tags: [runbook, homeassistant, migration, pi]
---

# Migrate Home Assistant custom components

The pi configuration supplies `auth_oidc` 1.2.1 and
`adaptive_lighting` 1.32.0 from the pinned Nixpkgs input. Before the first
activation, stop Home Assistant and back up `/home/repparw/services/hass`.

Move these existing directories outside `custom_components`:

- `custom_components/auth_oidc`
- `custom_components/adaptive_lighting`

Apply the NixOS configuration, then confirm both paths were recreated as
symlinks into `/nix/store` and both integrations load successfully. Keep those
two integrations out of HACS update operations; update them through the pinned
Nixpkgs input instead.

For rollback, keep Home Assistant stopped, switch to the previous NixOS
generation, remove only the two Nix-store symlinks, restore the saved component
directories, then start Home Assistant and verify both integrations load.

HACS and `ai_automation_suggester` remain writable and outside this migration.

## Related

- [Host profiles](../hosts.md#pi)
- [Home Assistant service aspect](../../modules/aspects/services/homeassistant.nix)
- [Secret inventory](../architecture/secret-inventory.md)
