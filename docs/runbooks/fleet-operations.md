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
complete. Alpha's home-state exporter publishes fresh files and verified
SQLite snapshots even when one database stays locked. Failed SQLite snapshots
use a previous verified copy with its original timestamp, or are omitted if
none exists. The export is marked **degraded**, not complete. A 15-minute
timer retries only missing/stale databases and starts a new offsite upload
after recovery. Degraded backups cannot advance the complete-backup success
stamp or permit pruning.

Inspect `/var/lib/home-state-backup/offsite/.export-status.json` for failed
databases and their last verified times, and `/var/lib/backup-exports/offsite.json`
for the complete backup verdict. Confirm native database integrity and perform
an isolated restore before relying on a recovery point.

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

Pi's 05:30 timer resolves the current GitHub `main` revision through Nix
and checks that the exact SHA passed CI. Unchanged revisions are attempted
only once by the unattended timer, even after failure; a new commit is
eligible for the next run. Use `fleet-update deploy --force` for an
authorized retry of the same revision.

deploy-rs builds selected hosts, activates their system profiles, and
handles activation/SSH rollback. There are no custom per-service health
gates or fallback rollbacks. Application failures are monitored
independently and investigated, not automatically rolled back.

The controller and headless reboot service share a lock so deployments
and reboots cannot overlap. Local worktree commands (`nix run .#deploy` and
`nix run .#deploy-rs`) archive the worktree to the controller and launch a
transient systemd deployment under that same lock. If the SSH connection
drops, the controller-owned job continues; inspect its named
`fleet-worktree-deploy-*.service` journal before retrying. After a successful
scheduled deployment, the existing headless reboot service may reboot
Epsilon or Pi for new kernel/initrd generations when backups permit. Alpha
remains manual; the nightly 03:00 reboot timer is the fallback.

Inspect the controller log after a failure:

```sh
journalctl -u fleet-deploy-run --no-pager
fleet debug pi
```

If deploy-rs cannot restore an earlier generation, follow
[manual rollback](update-rollback.md). The last automatic attempt SHA
is kept in `/var/lib/auto-update/last-attempted-revision`. Its paired
`last-attempt-status` is 2 while running, 1 on failure, and 0 on success;
Grafana Cloud uses these durable facts to report failures and stalled runs. Direct deploy-rs and
`--dry-activate` are separate authorized live operations, not PR checks.
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
