---
type: Runbook
title: Update Rollback
description: Roll back a bad update on pi or alpha, whether it came from the nightly pipelines or a manual switch.
when: Read when pi or alpha flipped to a generation that misbehaves, or when a nightly update cycle reports ROLLED BACK and you need to inspect or recover further.
resource: modules/hosts/pi.nix
tags: [runbook, recovery, updates, pi, alpha]
---

# Update Rollback

Two pipelines update the fleet, and both own their rollback:

- **pi** (`auto-update.timer`, 04:15): the sole flake.lock writer. Bumps
  inputs, builds, pushes the lock to main, flips, soaks against strict
  local probes, and rolls back automatically on soak failure — pushing a
  revert commit so origin/main always matches what production converged
  on. Two consecutive rollbacks trip the breaker: automation writes its
  own PAUSE flag and stops.
- **alpha** (`alpha-auto-update.timer`, 05:30): a pure consumer. Pulls
  main, defers while your graphical session is active or pi is
  unhealthy, flips, soaks, rolls back with the same breaker pattern.

Full pipeline detail lives in the
[fleet operations runbook](fleet-operations.md).

## Automatic rollback

Both pipelines handle the common case themselves: soak failure triggers
`nixos-rebuild switch --rollback` and a Discord alert with the diff
attached. If you see `ROLLED BACK` in #notifications, check what broke
before the next cycle:

```sh
journalctl -u auto-update -b          # pi
journalctl -u alpha-auto-update -b    # alpha
```

## Manual rollback

For a regression that surfaces outside the soak window (or after a
manual `nrs`), switch back to the previous generation:

```sh
nix-env --list-generations --profile /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system-<generation>-link/bin/switch-to-configuration switch
```

A reboot-old-entry works too: alpha uses systemd-boot, pi uses extlinux
via the Pi firmware.

## After a rollback

1. Find why the new generation misbehaved (journal, fleet-health
   counters in `/var/lib/fleet-health/`).
2. On pi, the bad lock commit was already reverted by the pipeline. If
   it was paused by the breaker, inspect and then resume:

   ```sh
   ssh root@pi 'rm /var/lib/auto-update/PAUSE'    # resume automation
   ssh root@pi 'touch /var/lib/auto-update/PAUSE' # pause manually
   ```

3. Verify before the next cycle:

   ```sh
   nix flake check
   nh os switch   # alpha manual flip onto current main
   ```

## Related

- [Fleet operations](fleet-operations.md)
- [Den aspect composition](../architecture/den-aspect-composition.md)
