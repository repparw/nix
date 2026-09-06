---
type: Runbook
title: Update Rollback
description: Recover any fleet node from a bad deploy-rs activation, failed soak, or manual switch.
when: Read when a node misbehaves after activation, or when the staged fleet updater reports a rollback that needs inspection or recovery.
resource: modules/deploy.nix
tags: [runbook, recovery, updates, pi, alpha, epsilon, deploy-rs]
---

# Update Rollback

Pi's 04:15 promotion job is the sole `flake.lock` writer and exits after
publishing a validated candidate. The independent 05:30 consumer deploys exact
current main in the order epsilon, pi, then idle alpha. Pi's 07:00 alpha retry
only retries convergence if the desktop was deferred or unreachable.

Full pipeline detail lives in the
[fleet operations runbook](fleet-operations.md).

## Automatic rollback

The updater handles the common cases itself. deploy-rs magic rollback covers a
failed activation. A failed soak reverts main when the cycle created a lock
candidate, redeploys the reverted graph to every node already reached, and
falls back to each node's exact pre-update profile if necessary. Check the
controller and retry journals before the next cycle:

```sh
journalctl -u fleet-promote -b      # pi producer
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
2. If the controller created the bad lock commit, confirm the updater's revert
   reached `origin/main`. If it was paused by the breaker, inspect and resume:

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
- [Den aspect composition](../architecture/den-aspect-composition.md)
