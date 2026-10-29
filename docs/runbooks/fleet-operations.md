---
type: Runbook
title: Fleet operational reference
description: Retained failure evidence, backup consistency, controller deployment and rollback semantics, and host-specific maintenance safeguards.
when: Read when diagnosing fleet failures, interpreting backup coverage, investigating deployment or rollback state, or planning storage and firmware maintenance. Use the fleet-operations skill to carry out operational tasks.
resource: modules/deploy.nix
tags:
  [runbook, pi, alpha, epsilon, backups, restic, alerting, upgrades, deploy-rs]
---

# Fleet operational reference

The [fleet-operations skill](../../.agents/skills/fleet-operations/SKILL.md)
is the entrypoint for **live** inspection and authorized operations. This
runbook records the constraints and recovery details behind those commands,
not a second general-purpose action checklist. For proposed configuration
changes use [verify-fleet-change](../../.agents/skills/verify-fleet-change/SKILL.md).

## Retained failures and health

Grafana Cloud owns periodic health alerts; see [monitoring](monitoring.md)
for delivery failures and [Cloud alert configuration](grafana-cloud.md) for
notification policy. `fleet health probe` is read-only and `--strict`
tests deployment readiness without requiring Cloud availability or unrelated
failed scheduled jobs.

Failed scheduled jobs remain in `/var/lib/fleet-unit-state/<unit>` until a
successful rerun. Success stamps live in `.success/<unit>`; a job that has
never run has no success stamp. `systemctl reset-failed` does **not**
clear retained failure evidence. Repair and rerun the underlying unit rather
than deleting its record to make health appear green.

Use the generated `fleet` command surface for routine host diagnostics.
For a deeper investigation, `fleet-unit-snapshot` captures the current
systemd state; inspect retained evidence on the owning host. Report missing
or permission-limited files as unavailable, not healthy.

## Offsite backup coverage and consistency

The `restic-backups-offsite.service` timer runs nightly. Each manual start
follows the same export preparation, upload, repository check, and retention
path. Check `/var/lib/backup-exports/offsite.json` alongside the unit result:
failed, stale, empty, or unchanged producer exports make a snapshot explicitly
**incomplete** even when other data uploads successfully. An incomplete
export skips pruning. A new snapshot alone is not a complete recovery point.

Arr apps write native scheduled archives; the backup job checks their age
and nonzero size, not ZIP or SQLite integrity. After restoring an Arr app,
confirm its persisted daily backup schedule, 28-day retention, and Bazarr's
midnight backup. Producer registrations are declared by each host's
`provides.backup`; retention and implementation live in
[backup.nix](../../modules/aspects/backup.nix).

Before changing coverage or storage, compare the evaluated Restic paths and
exclusions with the physical mount layout, including same-device bind mounts:

```sh
nix eval .#nixosConfigurations.alpha.config.services.restic.backups.offsite.paths --json --no-update-lock-file
nix eval .#nixosConfigurations.alpha.config.services.restic.backups.offsite.exclude --json --no-update-lock-file
```

Pi and Epsilon compose [host-backup](../../modules/aspects/host-backup.nix).
Alpha selects home-state roots in [alpha.nix](../../modules/hosts/alpha.nix),
then backs up its private `offsite` staging tree. The separate HDD mirror
includes `.config`, `.local`, `Games`, and `Projects` (including OpenTofu
state); Pictures and Documents have their own sync job. Age keys are staged
only for the HDD mirror. Restored staging data belongs under the user's home,
not the staging path.

Some Alpha home-state SQLite files are raw copies, **not transactional
exports**. Pi's [service exporter](../../modules/aspects/pi-services-backup.nix)
produces consistent SQLite snapshots and publishes only complete
generations. Alpha's old copies of Pi data are historical, not current.
Filesystem copies alone do not establish a consistent application backup.

Use [host recovery](host-recovery.md) or
[service restoration](restore-service-backups.md) for isolated restore
instructions. Never substitute a successful backup upload for an actual
restore/integrity test.

### After an OpenTofu state change

After an authorized `tofu apply`, import, state migration, or manual repair
on Alpha, refresh **both** the local HDD and offsite copies in order:

```sh
sudo systemctl start --wait home-state-backup-offsite.service
sudo systemctl start --wait rsync-job-bupstate.service
sudo systemctl start --wait restic-backups-offsite.service
```

The first updates the offsite staging tree, the second mirrors that state
to the HDD, and the third uploads and applies its normal backup policy.
Verify each unit and the export report; stop to investigate a failure instead
of reporting complete coverage. Do not put these commands in a hook around
OpenTofu itself: a backup failure must not fail or retry a successful
infrastructure change.

The [OpenTofu restore reference](host-recovery.md#restore-the-opentofu-state)
describes the exact state paths and independent restore procedure.

## Controller deployment and recovery

Pi is the serialized production deployment controller (configured by
[deploy.nix](../../modules/deploy.nix)). It checks successful CI for the
**exact current main revision**, captures prior system profiles and roots,
and prepares all selected targets before activation. CI host checks use
package stubs and do not replace full preparation builds.

The transaction activates Epsilon, idle Alpha, then Pi, with deploy-rs
confirmation and health checks. Streaming or an active session can defer
Alpha; the retry timer consumes current `main` later. `main` is desired
state, while `/var/lib/auto-update/deployed-revision` records the last
revision verified across the **entire** fleet. A deferred host does not
advance that marker.

The controller's `/var/lib/auto-update/latest-preparation` points to
captured revision and prepared profiles/results. Per-host
`fail-<host>.log` files survive controller reboots, though later attempts
replace them. The transient deploy unit's journal may not survive a reboot.
Investigate on Pi:

```sh
cat /var/lib/auto-update/latest-preparation
less /var/lib/auto-update/fail-alpha.log
journalctl -u fleet-deploy-run -u fleet-alpha-retry --no-pager
```

A preparation failure pauses before activation. A failed activation uses
deploy-rs rollback and restores rooted earlier systems on hosts reached in
the transaction; failed rollback retains those roots for rescue. Build or
activation failures pause automation immediately, while soak failures use
a two-cycle breaker. The controller does not revert Git `main`.
See [update rollback](update-rollback.md) for manual recovery and the
post-incident checklist.

`/var/lib/auto-update/PAUSE` inhibits ordinary automation; only remove it
after diagnosis and approval. `fleet-update --force` requires an explicitly
selected host, bypasses PAUSE and activity gates **without removing PAUSE**,
and retains CI, locking, health checks, and rollback. Alpha's `Mod+U`
uses this forced controller path. Bypassing an activity gate is not a
routine retry strategy.

A local-tree `nix run .#deploy-rs -- .#alpha --dry-activate` is a
**separate authorized operational path**: it can build and contact a target.
It is not a read-only PR verification step or a substitute for
`fleet-update deploy`.

Deployment implementation:
[fleet-update.sh](../../modules/scripts/fleet-update.sh).
Input publication is independent:
[lock update workflow](../../.github/workflows/lock-update.yml) and
[upstream watcher contracts](../../.github/upstream/README.md).
A runtime readiness report alone does not retire an upstream workaround.

## Storage and firmware safeguards

Nix `min-free` and `max-free` control reclamation of unreferenced paths
during builds. Thresholds and generation policies are configured in
[defaults](../../modules/defaults.nix) and host modules.

Alpha's [root Btrfs health job](../../modules/aspects/btrfs-maintenance.nix)
tries empty-chunk reclamation and one bounded low-usage pass, then checks
again. It does not balance media disks automatically. Interrupting the
client does not necessarily stop a kernel Btrfs balance.

Pi's [generation policy](../../modules/aspects/pi-generation-retention.nix)
preserves the five latest generations and the selected, running, and booted
systems. It shares the controller's deployment lock and protects rollback
and preparation roots. Inspect with `pi-generation-retention plan` before
an authorized `apply` or `nix-gc.service`. Avoid
`nix-collect-garbage -d`, which bypasses this policy. Confirm retained
roots are outside the rollout/rollback window before deleting anything.

On hosts with fwupd, `fwupdmgr get-updates` shows available firmware.
Refreshing metadata and applying `fwupdmgr update` are live changes;
firmware can require a reboot. UEFI capsule updates require the EFI
system partition mounted at `/boot`. Schedule firmware work separately
from fleet deployments.
