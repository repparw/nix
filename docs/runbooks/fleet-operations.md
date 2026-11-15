---
type: Runbook
title: Fleet failure and recovery constraints
description: Safety rules for interpreting fleet failures, backups, deployments and storage cleanup.
when: Read when investigating a deployment failure, an incomplete backup, or a risky maintenance action. Use the fleet-operations skill for normal commands.
resource: modules/deploy.nix
tags: [runbook, recovery, backups, deployments, pi, alpha, epsilon]
---

# Fleet failure and recovery constraints

Normal operations belong in the
[fleet-operations skill](../../.agents/skills/fleet-operations/SKILL.md). The
implementation lives in [fleet-update.sh](../../modules/scripts/fleet-update.sh)
and the Nix modules that own each piece. This page records how failures behave,
because a successful exit code or a new Nix generation cannot tell you that.

## Retained failures and health

A failed scheduled job leaves evidence in `/var/lib/fleet-unit-state/` until the
job succeeds. `systemctl reset-failed` does not clear that evidence. A missing
success stamp means no one has observed the job succeeding. It does not mean the
job is healthy.

`fleet health probe --strict` measures deployment readiness. It does not require
Grafana Cloud to be available or unrelated scheduled jobs to pass. Missing
telemetry and unreachable hosts count as _unknown_, not green. Read
[monitoring](monitoring.md) before you decide that an alert is resolved.

## Offsite backup coverage and consistency

A successful Restic upload does not always give you a usable application
restore. The export report at `/var/lib/backup-exports/offsite.json` separates
fresh application exports from missing, failed, or stale producers. An
incomplete export blocks pruning, but it does not make the uploaded data
complete. Before you rely on a recovery point, confirm native database integrity
and do an isolated restore.

Persistence is not offsite backup coverage. Bound paths, nested devices,
`--one-file-system`, and live SQLite data can change what Restic captures. For
the restore procedure, use [host recovery](host-recovery.md) and
[service restoration](restore-service-backups.md). To see the backup roots,
inspect the evaluated configuration instead of trusting a list in Markdown.

After an authorized OpenTofu state change on Alpha, refresh the staging tree
before the offsite upload:

```sh
sudo systemctl start --wait home-state-backup-offsite.service
sudo systemctl start --wait restic-backups-offsite.service
```

Check that both commands succeeded, and read the export report. Do not make a
successful `tofu apply` depend on backup success by wrapping it in a backup
hook. See [OpenTofu state recovery](host-recovery.md#restore-the-opentofu-state).

## Controller deployment and recovery

The controller requires successful CI for the **exact current main revision**.
It prepares all selected targets before it activates any of them, and then
activates each host with per-host service health checks. A successful build, SSH
confirmation, or one healthy host does not show that the fleet has converged.
The controller records the last fully verified revision separately from the
desired Git `main`, and a failure does not revert Git.

After a successful deployment, the controller may reboot headless Epsilon and Pi
to activate staged kernel or initrd changes. Backup and health checks can defer
those reboots. Alpha reboots stay manual. The
[headless reboot implementation](../../modules/scripts/fleet-headless-reboot.sh)
defines the exact sequence and retry behavior.

If activation fails, deploy-rs rolls back, and the controller restores the
earlier systems on the hosts it reached. Preparation and activation errors pause
automation immediately. Repeated soak errors trip a separate circuit breaker.
The controller deliberately keeps rollback roots when recovery fails. Do not
delete them, clear `/var/lib/auto-update/PAUSE`, or repeat a forced deployment
just to hide the error.

Investigate on the controller:

```sh
cat /var/lib/auto-update/latest-preparation
less /var/lib/auto-update/fail-alpha.log
journalctl -u fleet-deploy-run --no-pager
```

Preparation evidence is bounded. The per-host prepare log keeps only its tail,
so the explanation of a failed build is at the end of the log. The run refuses
to start when the state filesystem has no room for that log. A full state
filesystem therefore aborts the update instead of truncating the log again. The
[controller implementation](../../modules/scripts/fleet-update.sh) defines the
exact bounds.

Use [manual rollback](update-rollback.md) if automatic recovery did not restore
the affected host. The [controller implementation](../../modules/scripts/fleet-update.sh)
is authoritative for current ordering, timeouts, and retry behavior.

`--force` bypasses PAUSE without deleting it, but it still needs explicit
authorization. Running `deploy-rs` directly, or with `--dry-activate`, is a
separate live operation. It does not replace controller deployment or PR
verification. The
[verification skill](../../.agents/skills/verify-fleet-change/SKILL.md) does not
change live hosts.

## Storage and firmware safeguards

Pi's generation cleanup protects active, selected, and controller-rooted
rollback systems. Before an authorized cleanup, run
`pi-generation-retention plan`. Do not use `nix-collect-garbage -d`, which
bypasses that policy. An interrupted Btrfs balance can continue in the kernel,
so inspect the device before you retry.

Firmware updates and storage repartitioning are separate maintenance
operations. A NixOS generation rollback cannot repair a missing filesystem or an
unbootable initrd. Keep a tested console or rescue path, and follow
[host persistence](host-persistence.md) before you modify storage.
