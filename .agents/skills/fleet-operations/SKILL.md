---
name: fleet-operations
description: Inspect and operate the running NixOS fleet. Use for host diagnostics, retained failures, backup checks and manual runs, production deployment, storage maintenance, or firmware updates; require authorization before changes to live state.
---

# Fleet operations

Use this skill for live fleet operations. To check a proposed configuration
change before deployment, use
[verify-fleet-change](../verify-fleet-change/SKILL.md). Evaluations and builds
do not show that a running host is healthy.

This skill does not describe every supported command. To list the commands
installed on the host, run:

```sh
fleet commands --json
```

## Choose the operation

Name the target hosts, the symptom or requested outcome, and whether the
operation only reads state. Inspect before you change anything. An unreachable
host, a missing status file, or a successful build does not show that the fleet
is healthy.

Pick the route that fits the task.

- **Health or alerts.** Run `fleet health probe` and `fleet debug <host>`. Read
  the [retained-failure reference](../../../docs/runbooks/fleet-operations.md#retained-failures-and-health).
- **Backup status or failed exports.** Run `fleet backup status`. Read the
  [offsite coverage rules](../../../docs/runbooks/fleet-operations.md#offsite-backup-coverage-and-consistency)
  before you act.
- **Production deployment or retry.** Follow the
  [controller transaction](../../../docs/runbooks/fleet-operations.md#controller-deployment-and-recovery).
  Never replace it with a direct deploy-rs switch.
- **Storage pressure or generation cleanup.** Read the
  [storage safeguards](../../../docs/runbooks/fleet-operations.md#storage-and-firmware-safeguards).
- **Firmware.** List the available updates first. Refreshing and installing
  change state, so treat them separately from ordinary fleet deployments.

## Actions that need authorization

Do not take any of these actions unless you are authorized for that specific
action:

- Start services.
- Back up or prune data.
- Change PAUSE.
- Deploy or roll back.
- Collect garbage.
- Update firmware.

Using `--force` to bypass PAUSE needs its own explicit authorization. A
deploy-rs `--dry-activate` run is not read-only. It can build outputs and
contact the target, so it also needs authorization.

## Inspect without changing the fleet

Run only the commands that fit the task, and replace `alpha` with the affected
host.

```sh
fleet health probe
fleet health probe --strict
fleet backup status
fleet debug alpha
```

`--strict` checks deployment readiness. It does not treat unrelated failed jobs
or Grafana Cloud availability as deployment prerequisites. `fleet debug`
produces a bounded diagnostic bundle for the host. Report anything you could not
reach, or lacked permission to read, as unknown rather than passing.

Failed scheduled jobs leave evidence in `/var/lib/fleet-unit-state/` on the
host that owns the job. Only a successful rerun clears that evidence.
`systemctl reset-failed` does not. For missing telemetry, read
[monitoring](../../../docs/runbooks/monitoring.md).

## Run a backup and check that it is complete

Run these commands on the host that owns the backup unit, and only after
authorization.

```sh
sudo systemctl start --wait restic-backups-offsite.service
journalctl -u restic-backups-offsite.service -n 100 --no-pager
sudo cat /var/lib/backup-exports/offsite.json
```

Check both the unit result and the export report. An uploaded Restic snapshot
does not mean the application backup is complete. A stale or failed producer can
mark the report incomplete, and that blocks pruning. A successful unit status
does not replace checking export coverage and freshness.

After an authorized OpenTofu state change on Alpha, run the backup units in the
documented order. They stage the state for offsite and then upload it. See the
[state recovery reference](../../../docs/runbooks/host-recovery.md#restore-the-opentofu-state).
Do not attach backups to `tofu apply` as hooks.

Restoring host or service data is a separate workflow with higher risk. Read
[host recovery](../../../docs/runbooks/host-recovery.md) or
[service restore](../../../docs/runbooks/restore-service-backups.md). Prefer a
restore rehearsal in an isolated environment over overwriting live state.

## Deploy only with explicit approval

Pi is the fleet deployment controller. Confirm its current address in
`modules/deploy.nix` or in the evaluated fleet options. The controller checks
CI for the exact current `main`, prepares the selected hosts, and runs deploy-rs
with health checks and rollback.

With authorization, run this on Pi:

```sh
fleet-update deploy --host alpha --wait-lock 7200
```

Replace the host with the scope you were given. Run the command on the
controller, not on another host. Deploying selected hosts does not show that the
whole fleet has converged. Before you retry, read
`/var/lib/auto-update/latest-preparation`, the host failure logs, and the
controller journals.

Reviewing a local tree with deploy-rs is a separate operation that needs its own
authorization:

```sh
nix run .#deploy-rs -- .#alpha --dry-activate
```

This is not the controller's production transaction.

If you have already verified the exact contents of a local tree,
`nix run .#deploy -- .#alpha` skips the repeated flake checks in deploy-rs. It
does not verify anything itself. For unverified changes, use
`nix run .#deploy-rs -- .#alpha`. Both commands are operational actions that
need authorization. Neither is a PR check.

Before you manually restore a generation or resume a paused controller, read
[rollback and recovery](../../../docs/runbooks/update-rollback.md).

## Maintain only the requested resource

On Pi, preview generation retention first:

```sh
pi-generation-retention plan
```

Apply retention or run `nix-gc.service` only with authorization. Do not run
`nix-collect-garbage -d`, because it bypasses Pi's retention policy.

For firmware, list updates with `fwupdmgr get-updates`. Schedule and authorize
the refresh, the installation, and any required restart separately. Host-specific
limits are in the
[storage and firmware reference](../../../docs/runbooks/fleet-operations.md#storage-and-firmware-safeguards).

## Report

Record the target hosts, the operation, what the authorization covered, the
commands, the observations before and after, the exit status of each command,
missing evidence, and remaining risks. For a deployment, also record the exact
revision, the hosts reached, and health after activation. Do not report
fleet-wide success from one healthy host.
