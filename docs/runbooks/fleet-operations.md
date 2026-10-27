---
type: Runbook
title: Fleet health, backups, and deployment
description: Inspect failures, run backups, deploy main, and maintain storage.
when: Read when a Discord health alert fires, when restoring service state from the offsite repo, or when a staged fleet update deploys, defers, or rolls back.
resource: modules/deploy.nix
tags:
  [runbook, pi, alpha, epsilon, backups, restic, alerting, upgrades, deploy-rs]
---

# Fleet health, backups, and deployment

Pi is the deployment controller. Agents use the
[fleet operations skill](../../.agents/skills/fleet-operations/SKILL.md) and
[configuration verification skill](../../.agents/skills/verify-nixos-config/SKILL.md).
Discover the installed commands with `fleet commands --json`.

## Inspect health and retained failures

Grafana Cloud owns periodic health alerts. See [monitoring](monitoring.md) for
telemetry diagnostics and [Cloud alert configuration](grafana-cloud.md) for policy.
`fleet health probe` is read-only; `--strict` checks deployment readiness without
making Cloud availability or unrelated failed jobs deployment prerequisites.

```sh
fleet debug alpha
fleet backup status
sudo fleet-unit-snapshot
sudo ls -l /var/lib/fleet-unit-state
```

Failed scheduled jobs persist in `/var/lib/fleet-unit-state/<unit>` until a
successful rerun. Success timestamps live in `.success/<unit>`.
`systemctl reset-failed` does not clear retained evidence. Repair and rerun the
job; removing its record does not prove recovery. Jobs that have never run
have no success record.

## Run the scheduled offsite operation

```sh
sudo systemctl start --wait restic-backups-offsite.service
journalctl -u restic-backups-offsite.service -n 100 --no-pager
```

The same service runs on the nightly timer. It prepares registered exports,
uploads available data, and checks the repository. A failed or stale export
makes the overall run incomplete and skips pruning, while other data still
uploads. Inspect `/var/lib/backup-exports/offsite.json`; an uploaded snapshot
alone does not establish complete application coverage.

After changing infrastructure state outside Git — a `tofu apply`, import,
state migration, or manual state repair on alpha — capture a fresh backup of
the OpenTofu state immediately:

```sh
sudo systemctl start --wait home-state-backup-offsite.service
sudo systemctl start --wait restic-backups-offsite.service
```

Run it manually and never from a hook inside the infrastructure change
itself: a failed backup must not fail or retry an otherwise successful
operation. See [state recovery](host-recovery.md#restore-the-opentofu-state).

Arr apps use native scheduled archives; the job checks freshness and size,
not ZIP or SQLite integrity. After installing or restoring them, check their
persisted settings: daily backups, 28-day retention, and Bazarr at midnight.
The other producer units run through this job. Ownership and registrations
live in each host's `provides.backup`; implementation and retention are in
[backup.nix](../../modules/aspects/backup.nix).

Check scope before changing storage:

```sh
nix eval .#nixosConfigurations.alpha.config.services.restic.backups.offsite.paths --json
nix eval .#nixosConfigurations.alpha.config.services.restic.backups.offsite.exclude --json
```

Pi and Epsilon compose [host-backup](../../modules/aspects/host-backup.nix).
Alpha selects home state in [alpha.nix](../../modules/hosts/alpha.nix), then
backs up the whole private `offsite` staging tree. Those home-state SQLite
files are raw copies, not transactional exports. Age keys are staged only for
the separate HDD mirror. That mirror includes `.config`, `.local`, `Games`,
and `Projects` (the staged OpenTofu state); Pictures and Documents have their
own sync job. Restoring staged home state
means placing it beneath the user's home, not its original staging path.

Pi's [service exporter](../../modules/aspects/pi-services-backup.nix) produces
transaction-consistent SQLite snapshots and publishes a generation only after
all files succeed. Alpha's old Pi copies are historical, not current backups.

Use [host recovery](host-recovery.md) or [service restoration](restore-service-backups.md)
for an isolated restore. Live filesystem copies are not atomic database backups.

## Deploy current main

```sh
ssh root@192.168.0.4 'fleet-update deploy --host alpha --wait-lock 7200'
```

The controller requires successful CI for the exact main revision, captures
immutable profiles, and builds every selected target before activation.
CI's stubbed host checks do not replace full builds. Activation proceeds through
Epsilon, Alpha, and Pi with health checks and deploy-rs confirmation. Active
sessions or streams can defer Alpha; the retry timer consumes current main later.

Main is desired state. `/var/lib/auto-update/deployed-revision` records the last
revision verified across the fleet; a deferred host leaves that value unchanged.

Inspect failures on Pi:

```sh
cat /var/lib/auto-update/latest-preparation
less /var/lib/auto-update/fail-alpha.log
journalctl -u fleet-deploy-run -u fleet-alpha-retry --no-pager
```

The preparation directory contains captured revisions, profiles, results, and
logs. Per-host `fail-<host>.log` files survive controller reboots but are replaced
by later deploys. The transient unit's journal may not survive a reboot.

Preparation failures pause before activation. Activation failures use deploy-rs
and restore the rooted prior systems on reached hosts. Failed rollback retains
the roots for rescue. Build or activation failures pause immediately; soak
failures use a two-cycle breaker. See [rollback](update-rollback.md).

```sh
ssh root@192.168.0.4 'touch /var/lib/auto-update/PAUSE'
ssh root@192.168.0.4 'rm /var/lib/auto-update/PAUSE'
```

Resume only after diagnosing the failure. `--force` requires an explicit host
and bypasses pause/activity gates while preserving the PAUSE file. It retains
CI, serialization, health checks, and rollback. Alpha's `Mod+U` uses this forced
controller path. For a local-tree review, use
`nix run .#deploy-rs -- .#alpha --dry-activate`; such a review, including
`--dry-activate`, is authorized operational work — it can realize deployment
outputs and contact the target, and it is not a PR verification step.

Implementation: [fleet-update.sh](../../modules/scripts/fleet-update.sh).
Lock publication: [lock-update workflow](../../.github/workflows/lock-update.yml)
and [upstream watcher contracts](../../.github/upstream/README.md).
Run `gh workflow run lock-update.yml` to request a lock update; publication and
deployment remain separate. Runtime readiness reports do not retire a watcher
until its declared completion conditions pass.

## Maintain storage

Nix's `min-free` and `max-free` control collection of unreferenced store paths
during builds. Thresholds and generation policies live in
[defaults](../../modules/defaults.nix) and the host declarations.
Alpha's [root Btrfs health job](../../modules/aspects/btrfs-maintenance.nix)
tries empty-chunk reclamation and one limited low-usage pass, then rechecks.
Unresolved pressure still fails. It never reclaims media disks automatically.
Chunk count bounds reclamation; killing the client can leave kernel balancing running.

Pi's [generation policy](../../modules/aspects/pi-generation-retention.nix)
keeps five recent system generations plus the selected, running, and booted
systems. It shares the deployment lock and preserves separate preparation and
rollback roots. Preview before cleanup:

```sh
ssh root@192.168.0.4 'pi-generation-retention plan'
```

An authorized cleanup uses `pi-generation-retention apply` or `nix-gc.service`.
Avoid `nix-collect-garbage -d`, which bypasses that policy. Separately rooted
builds can still fill the store; inspect old roots only after their rollout and
rollback window are complete.

## Update device firmware

On a host configured with fwupd:

```sh
fwupdmgr refresh
fwupdmgr get-updates
fwupdmgr update
```

Firmware can require a device or host reboot. UEFI capsule updates require the
ESP mounted at `/boot`. Schedule that interruption separately from fleet deploys.
