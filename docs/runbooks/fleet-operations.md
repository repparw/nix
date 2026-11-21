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

A successful Restic upload does not guarantee a complete application restore.
Failed or degraded exports must not allow retention pruning. Earlier complete
Restic snapshots remain available even when an export fails.

Alpha backs up curated ordinary home files directly, but live SQLite databases
need consistent snapshots because their WAL files may contain committed changes.
SQLite snapshots use tmpfs to avoid unnecessary SSD writes; they disappear on
reboot. If a database cannot be refreshed, the backup may contain a last
verified copy or omit it and is reported as degraded. The normal daily backup
schedule provides the next attempt.

OpenTofu state is read live, so avoid overlapping a manual state change with a
backup. Helium intentionally excludes cookies, caches, and tracking state:
restoring its selected files will not restore website logins.

The Nix configuration and export scripts define backup selection and behavior.
Use [host recovery](host-recovery.md) and
[service restoration](restore-service-backups.md) to recover data.

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
