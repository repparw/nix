---
name: fleet-operations
description: Inspect and operate the running NixOS fleet. Use for host diagnostics, retained failures, backup checks and manual runs, production deployment, storage maintenance, or firmware updates; require authorization before changes to live state.
---

# Fleet operations

Use this skill for **live** fleet operations. For proposed configuration
changes and pre-deployment evaluation, use
[verify-fleet-change](../verify-fleet-change/SKILL.md). Evaluation and builds
do not prove runtime health.

Discover the actual installed fleet commands instead of assuming this skill
describes every supported command:

```sh
fleet commands --json
```

## Select the operation and its boundary

Identify the target host(s), the observed symptom or requested outcome, and
whether the operation is read-only. Inspect first; do not infer a healthy
fleet from an unreachable host, a missing status file, or a successful build.

- **Health or alerts:** use `fleet health probe`, `fleet debug <host>`,
  and the [retained-failure reference](../../../docs/runbooks/fleet-operations.md#retained-failures-and-health).
- **Backup status or failed exports:** use `fleet backup status`; inspect
  the [offsite coverage rules](../../../docs/runbooks/fleet-operations.md#offsite-backup-coverage-and-consistency)
  before taking action.
- **Production deployment or retry:** follow the
  [controller transaction](../../../docs/runbooks/fleet-operations.md#controller-deployment-and-recovery).
  Never substitute a direct deploy-rs switch for the controller transaction.
- **Storage pressure or generation cleanup:** consult
  [storage safeguards](../../../docs/runbooks/fleet-operations.md#storage-and-firmware-safeguards).
- **Firmware maintenance:** discover updates first; treat refresh and install
  as state-changing operations, separate from ordinary fleet deployments.

Do not start services, back up or prune data, change PAUSE, deploy, roll back,
collect garbage, or update firmware unless authorized for that action.
`--force` needs explicit authorization to bypass pause/activity gates.
A deploy-rs `--dry-activate` is **not read-only**: it may build outputs and
contact the target, and also requires authorization.

## Inspect without changing the fleet

```sh
fleet health probe
fleet health probe --strict
fleet backup status
fleet debug alpha
```

Choose only the relevant command(s) and replace `alpha` with the affected
host. `--strict` checks deployment readiness; it does not make unrelated
failed jobs or Grafana Cloud availability deployment prerequisites. `fleet
debug` produces a bounded host diagnostic bundle. Report unreachable or
permission-limited observations as unknown, not as passing.

For retained scheduled-job failures, inspect
`/var/lib/fleet-unit-state/` on the owning host. A successful rerun clears
retained failure evidence; `systemctl reset-failed` alone does not. Read
[monitoring](../../../docs/runbooks/monitoring.md) for missing telemetry.

## Run a requested backup and establish completeness

On the host that owns the relevant backup unit, after authorization:

```sh
sudo systemctl start --wait restic-backups-offsite.service
journalctl -u restic-backups-offsite.service -n 100 --no-pager
sudo cat /var/lib/backup-exports/offsite.json
```

Inspect both the unit result and export report. An uploaded Restic snapshot
does not establish a **complete** application backup: stale or failed
producers can mark the report incomplete and prevent pruning. A successful
unit status is not a substitute for checking export coverage and freshness.

After an authorized OpenTofu state change on Alpha, run the three backup
units in the documented order for offsite staging, HDD mirroring, and
offsite upload. Use the [state recovery reference](../../../docs/runbooks/host-recovery.md#restore-the-opentofu-state);
do not attach backups as hooks to `tofu apply`.

Restoring host or service data is a separate, higher-risk workflow. Read
[host recovery](../../../docs/runbooks/host-recovery.md) or
[service restore](../../../docs/runbooks/restore-service-backups.md), and
prefer isolated restore rehearsal over overwriting live state.

## Deploy only with explicit approval

Pi is the fleet deployment controller; confirm its current address in
`modules/deploy.nix` or evaluated fleet options. The controller checks CI
for the exact current `main`, prepares selected hosts, and uses deploy-rs
with health checks and rollback. On Pi, the authorized operation is:

```sh
fleet-update deploy --host alpha --wait-lock 7200
```

Replace the host with the explicitly selected scope. Run this **on the
controller**, not on an arbitrary host. Alpha may defer for activity; a
deferred host does not mean fleet-wide deployment succeeded. Inspect
`/var/lib/auto-update/latest-preparation`, host failure logs, and controller
journals before retrying.

To review a local tree with deploy-rs, only when separately authorized:

```sh
nix run .#deploy-rs -- .#alpha --dry-activate
```

That path is distinct from the controller's production transaction.
See [rollback and recovery](../../../docs/runbooks/update-rollback.md)
before manually restoring a generation or resuming a paused controller.

## Maintain only the requested resource

Preview Pi generation retention first (on Pi):

```sh
pi-generation-retention plan
```

Apply retention or run `nix-gc.service` only with authorization. Avoid
`nix-collect-garbage -d`, which bypasses Pi's retention policy.
For firmware, inspect with `fwupdmgr get-updates`; refresh, installation,
and any required restart must be separately scheduled and authorized.
Use the [storage/firmware reference](../../../docs/runbooks/fleet-operations.md#storage-and-firmware-safeguards)
for host-specific constraints.

## Report

Record target hosts, operation, approval boundary, commands, before/after
observations, actual exit statuses, missing evidence, and remaining risks.
For deployment include the exact revision, reached/deferred hosts, and
post-activation health; never claim fleet-wide success from one healthy host.
