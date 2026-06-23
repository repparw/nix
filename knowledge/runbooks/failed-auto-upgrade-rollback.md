---
type: Runbook
title: Failed Auto-Upgrade Rollback
description: Recover from a failed automatic NixOS upgrade.
resource: modules/aspects/auto-upgrade.nix
tags: [runbook, recovery, auto-upgrade]
---

# Failed Auto-Upgrade Rollback

Auto-upgrade is enabled through `den.aspects.auto-upgrade` and updates every
flake input with `--commit-lock-file`.

1. Inspect the failed run:

   ```sh
   systemctl status nixos-upgrade.service
   journalctl -u nixos-upgrade.service -b
   git status
   git log --oneline -5
   ```

2. Boot or switch back to the previous working generation:

   ```sh
   sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
   sudo /nix/var/nix/profiles/system-<generation>-link/bin/switch-to-configuration switch
   ```

3. If auto-upgrade committed a bad lock update, revert that commit or restore
   the previous `flake.lock`, then verify before switching again:

   ```sh
   nix flake check
   nh os switch
   ```

## Related

- [Den aspect composition](../architecture/den-aspect-composition.md)
