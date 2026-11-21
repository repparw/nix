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
incomplete export prevents pruning; it does not make the uploaded data complete.

Alpha's curated ordinary home files are read **directly** by Restic. The
home exporter writes a NUL-delimited `.home-files` list for
`--files-from-raw`; no full copy of the selected home tree is made.
Only SQLite databases are snapshotted under
`/var/lib/home-state-backup/offsite`. SQLite snapshots are self-contained and
verified. Failed snapshots reuse their last verified copy with its original
timestamp or are omitted. The status report is marked **degraded**.
Every 15 minutes, a degraded export triggers the normal full offsite backup.
Degraded backups cannot advance the complete-backup stamp or permit pruning.

The offsite and Claro Restic services hold a shared advisory lock at
`/var/lib/home-state-backup/.stage.lock` while reading the SQLite export.
The exporter takes an exclusive lock to publish a new SQLite generation and
file list. This lock does not freeze ordinary home files. Run backups through
the managed systemd units so the file list and snapshots are prepared first.

Inspect `/var/lib/home-state-backup/offsite/.export-status.json` for failed
databases and verification times, and `/var/lib/backup-exports/offsite.json`
for the complete-backup verdict. Confirm native database integrity and perform
an isolated restore before relying on a recovery point.

Alpha includes only Helium's `Default/Bookmarks`, `Default/Preferences`,
`Default/Sessions/`, and `Local State` in the curated home backup. It excludes
`DIPS`, cookies, other browser databases and caches. Restoring these files
recovers bookmarks, preferences and potentially open tabs, but not
authenticated website sessions.

Persistence is not offsite backup coverage. Bound paths, nested devices,
`--one-file-system` and live SQLite data can affect what Restic captures.
Use [host recovery](host-recovery.md) and
[service restoration](restore-service-backups.md) for the restore procedure.
Inspect the evaluated backup roots rather than trusting a list in Markdown.

OpenTofu state files are read directly by Restic as ordinary selected home
files. There is no special provider-lock check or JSON validation. A state
change during backup may affect one recovery point; use another snapshot if
needed. See [OpenTofu state recovery](host-recovery.md#restore-the-opentofu-state).

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
