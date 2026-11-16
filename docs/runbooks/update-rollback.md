---
type: Runbook
title: Update Rollback
description: Recover a fleet node after a failed deploy-rs activation or manual switch.
when: Read when a node misbehaves after activation or native rollback needs inspection.
resource: modules/deploy.nix
tags: [runbook, recovery, updates, pi, alpha, epsilon, deploy-rs]
---

# Update Rollback

Pi's 05:30 timer requires successful CI for the exact current main SHA.
deploy-rs builds selected hosts concurrently and activates them sequentially,
with no custom host ordering or application-health soak. See
[fleet operations](fleet-operations.md).

## Automatic rollback

deploy-rs attempts to roll back failed or unconfirmed activations. This
is not a distributed atomic transaction; rollback may itself fail. The
controller does not maintain additional rollback roots or perform a second
round of activation. Inspect the journal and affected host:

```sh
journalctl -u fleet-deploy-run -b --no-pager
fleet debug alpha
```

## Manual rollback

For a regression discovered after activation (or after a manual
switch), select a known-good generation on the affected node:

```sh
nix-env --list-generations --profile /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system-<generation>-link/bin/switch-to-configuration switch
```

A reboot-old-entry works too: alpha and epsilon use EFI loaders; pi uses
extlinux via the Pi firmware.

## After a rollback

1. Inspect the service journal and retained job records in
   `/var/lib/fleet-unit-state/`.
2. Fix or explicitly revert the bad configuration through a PR. The next
   new main commit is eligible after its exact-SHA CI passes; the same
   failed SHA is skipped by the automatic timer.
3. To retry the unchanged SHA explicitly, run `fleet-update deploy --force`
   on Pi. For a single host, use `fleet-update deploy alpha`.
   Verify before an authorized retry:

   ```sh
   nix flake check
   nix run .#deploy-rs -- .#alpha --dry-activate
   ssh root@192.168.0.4 'fleet-update deploy alpha'
   ```

## Related

- [Fleet operations](fleet-operations.md)
- [Troubleshooting](../troubleshooting.md)
