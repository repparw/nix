---
type: Runbook
title: Update rollback
description: Recover any fleet node from a bad deploy-rs activation, failed soak, or manual switch.
when: Read when a node misbehaves after activation, or when the staged fleet updater reports a rollback that needs inspection or recovery.
resource: modules/deploy.nix
tags: [runbook, recovery, updates, pi, alpha, epsilon, deploy-rs]
---

# Update rollback

Pi's 05:30 consumer requires successful CI for exact current main, then
prepares every selected host concurrently before activating epsilon, alpha,
and finally pi. Full pipeline detail
lives in the [fleet operations runbook](fleet-operations.md).

## Automatic rollback

The updater handles the common cases itself. deploy-rs magic rollback covers a
failed activation. The controller saves and roots each host's pre-update system
before attempting activation. A failed deployment restores those systems on
every host reached during this revision, without reverting main. Check the
controller and retry journals before the next cycle:

```sh
less /var/lib/auto-update/fail-alpha.log  # on Pi; replace alpha with the failed host
journalctl -u fleet-deploy-run -b   # transient entries may be absent after reboot
```

## Manual rollback

For a regression that surfaces outside the soak window (or after a manual
switch), select the known-good generation on the affected node. Rollback
changes the active system, so obtain authorization before running it:

```sh
(
  nix-env --list-generations --profile /nix/var/nix/profiles/system
  printf 'Known-good generation number: ' >&2
  IFS= read -r generation
  printf '%s' "$generation" | grep -Eq '^[0-9]+$' || exit 1
  test -L "/nix/var/nix/profiles/system-${generation}-link" || exit 1
  sudo "/nix/var/nix/profiles/system-${generation}-link/bin/switch-to-configuration" switch
)
```

A previous generation can also be selected in the boot menu. Alpha and Epsilon
use EFI loaders; Pi uses extlinux through the Pi firmware.

## After a rollback

1. Inspect the per-host failure log, service journal, and retained job
   records in `/var/lib/fleet-unit-state/`.
2. Main still records the desired revision. Fix or explicitly revert a bad
   configuration through a PR and wait for CI on the resulting main commit.
   On Pi, inspect whether the controller is paused before changing its state:

   ```sh
   test -e /var/lib/auto-update/PAUSE && echo paused || echo not-paused
   ```

3. Verify the fix with focused Nix evaluations or existing checks from the
   [verification skill](../../.agents/skills/verify-fleet-change/SKILL.md)
   and confirm CI for the exact main commit. A full `nix flake check`
   is not a substitute for checking the behavior that failed.

4. Resuming automation and deploying are separate live operations. They
   require explicit authorization. After inspecting the failure and resolving
   the breaker, use the [fleet operations skill](../../.agents/skills/fleet-operations/SKILL.md)
   on Pi. If authorized, an operator may resume a paused controller with:

   ```sh
   sudo rm /var/lib/auto-update/PAUSE
   ```

   An explicitly authorized selected-host deployment runs on Pi:

   ```sh
   fleet-update deploy --host alpha --wait-lock 7200
   ```

   Do not use `--dry-activate` as a read-only validation step: it can build
   outputs and contact the target. The controller transaction is the production
   deployment path.

## Related

- [Fleet operations](fleet-operations.md)
- [Troubleshooting](../troubleshooting.md)