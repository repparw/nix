---
type: Runbook
title: Update Rollback
description: Recover any fleet node from a bad deploy-rs activation, failed soak, or manual switch.
when: Read when a node misbehaves after activation, or when the staged fleet updater reports a rollback that needs inspection or recovery.
resource: modules/deploy.nix
tags: [runbook, recovery, updates, pi, alpha, epsilon, deploy-rs]
---

# Update Rollback

GitHub Actions opens lock update PRs. Pi's independent 05:30 consumer requires
successful CI for exact current main, then prepares every selected host before
activating epsilon, idle alpha, and finally pi. Preparation failures pause
automation before activation starts and retain preparation evidence.
Pi's 07:00 alpha retry uses the same CI gate.

Full pipeline detail lives in the
[fleet operations runbook](fleet-operations.md).

## Automatic rollback

The updater handles the common cases itself. deploy-rs magic rollback covers a
failed activation. The controller saves and roots each host's pre-update system
before attempting activation. A failed deployment restores those systems on
every host reached during this revision, without reverting main. Check the
controller and retry journals before the next cycle:

```sh
journalctl -u fleet-deploy-run -b   # pi transient fleet consumer
journalctl -u fleet-alpha-retry -b  # pi alpha retry
```

## Manual rollback

For a regression that surfaces outside the soak window (or after a manual
switch), select the known-good generation on the affected node:

```sh
nix-env --list-generations --profile /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system-<generation>-link/bin/switch-to-configuration switch
```

A reboot-old-entry works too: alpha and epsilon use EFI loaders; pi uses
extlinux via the Pi firmware.

## After a rollback

1. Find why the new generation misbehaved (journal, fleet-health
   counters in `/var/lib/fleet-health/`).
2. Main still records the desired revision. Fix or explicitly revert a bad
   configuration through a PR and wait for CI on the resulting main commit.
   If deployment was paused by the breaker, inspect and resume:

   ```sh
   ssh root@192.168.0.4 'rm /var/lib/auto-update/PAUSE'    # resume automation
   ssh root@192.168.0.4 'touch /var/lib/auto-update/PAUSE' # pause manually
   ```

3. Verify before the next cycle:

   ```sh
   nix flake check
   nix run .#deploy-rs -- .#alpha --dry-activate
   ssh root@192.168.0.4 'fleet-update deploy --host alpha'
   ```

## Related

- [Fleet operations](fleet-operations.md)
- [Troubleshooting](../troubleshooting.md)
- [Den aspect composition](../architecture/den-aspect-composition.md)
