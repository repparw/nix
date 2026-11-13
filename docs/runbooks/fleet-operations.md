---
type: Runbook
title: Fleet failure and recovery constraints
description: Safety rules for interpreting fleet failures, backups, deployments and storage cleanup.
when: Read when investigating a deployment failure, an incomplete backup, or a risky maintenance action. Use the fleet-operations skill for normal commands.
resource: modules/deploy.nix
tags: [runbook, recovery, backups, deployments, pi, alpha, epsilon]
---

# Fleet failure and recovery constraints

Normal operations belong in the [fleet-operations skill](../../.agents/skills/fleet-operations/SKILL.md).
Implementation belongs in [fleet-update.sh](../../modules/scripts/fleet-update.sh)
and the owning Nix modules. This page records failure semantics that cannot
safely be inferred from a successful exit code or a Nix generation.

## Retained failures and health

A failed scheduled job leaves evidence in `/var/lib/fleet-unit-state/` until
the job succeeds. `systemctl reset-failed` does not clear that evidence.
A missing success stamp means the job has never been observed succeeding,
not that it is healthy.

`fleet health probe --strict` measures deployment readiness; it does not
require Grafana Cloud availability or unrelated scheduled jobs to pass.
Missing telemetry and unreachable hosts are _unknown_, not green. Consult
[monitoring](monitoring.md) before deciding an alert has been resolved.

## Offsite backup coverage and consistency

A successful Restic upload is not necessarily a usable application restore.
The export report at `/var/lib/backup-exports/offsite.json` distinguishes
fresh application exports from missing, failed or stale producers. An
incomplete export prevents pruning; it does not make the uploaded data
complete. Confirm native database integrity and perform an isolated restore
before relying on a recovery point.

Persistence is not offsite backup coverage. Bound paths, nested devices,
`--one-file-system` and live SQLite data can affect what Restic captures.
Use [host recovery](host-recovery.md) and
[service restoration](restore-service-backups.md) for the actual restore
procedure; inspect the evaluated backup roots rather than trusting a list
in Markdown.

After an authorized OpenTofu state change on Alpha, refresh the staging tree
before the offsite upload:

```sh
sudo systemctl start --wait home-state-backup-offsite.service
sudo systemctl start --wait restic-backups-offsite.service
```

Verify both commands and the export report. Do not make successful
`tofu apply` depend on backup success by wrapping it in a backup hook.
See [OpenTofu state recovery](host-recovery.md#restore-the-opentofu-state).

## Controller deployment and recovery

The controller enforces successful CI for the **exact current main revision**.
All selected targets must be prepared before any activation; host activation
then proceeds with per-host service health checks. A successful build,
SSH confirmation or one healthy host does not establish fleet convergence.
The last fully verified revision is recorded separately from desired Git
`main`; failure does not revert Git.

After a successful deployment, the controller may reboot headless Epsilon and
Pi to activate staged kernel or initrd changes. Backup and health gates can
defer those reboots; Alpha remains manual. The
[headless reboot implementation](../../modules/scripts/fleet-headless-reboot.sh)
owns the exact sequence and retry behavior.

A failed activation uses deploy-rs rollback and the controller restores
earlier systems on reached hosts. Preparation and activation errors pause
automation immediately; repeated soak errors trip a separate breaker.
Rollback roots are deliberately retained when recovery fails. Do not delete
them, clear `/var/lib/auto-update/PAUSE`, or repeat a forced deployment merely
to hide the error.

Investigate on the controller:

```sh
cat /var/lib/auto-update/latest-preparation
less /var/lib/auto-update/fail-alpha.log
journalctl -u fleet-deploy-run --no-pager
```

Preparation evidence is bounded. The per-host prepare log keeps only its tail,
so the explanation of a failed build is at the end of the log, and the run
refuses to start when the state filesystem has no room for that log. A full
card therefore aborts the update instead of truncating it again. The
[controller implementation](../../modules/scripts/fleet-update.sh) owns the
exact bounds.

Use [manual rollback](update-rollback.md) if automatic recovery did not
restore the affected host. The [controller implementation](../../modules/scripts/fleet-update.sh)
is authoritative for current ordering, timeouts and retry behavior.

`--force` bypasses PAUSE without deleting it, but still requires explicit
authorization. Direct `deploy-rs` or `--dry-activate` is a separate live
operation, not a substitute for controller deployment or PR verification.
The [verification skill](../../.agents/skills/verify-fleet-change/SKILL.md)
does not change live hosts.

## Storage and firmware safeguards

Pi's generation cleanup protects active, selected and controller-rooted
rollback systems. Use `pi-generation-retention plan` before an authorized
cleanup, not `nix-collect-garbage -d`, which bypasses that policy.
An interrupted Btrfs balance can continue in the kernel; inspect the device
before retrying.

Firmware updates and storage repartitioning are separate maintenance
operations. A NixOS generation rollback cannot repair a missing filesystem
or an unbootable initrd. Preserve a tested console/rescue path and follow
[host persistence](host-persistence.md) before modifying storage.
