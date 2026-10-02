---
type: Runbook
title: Fleet health, offsite backups, and auto-updates
description: How fleet-health alerting, offsite restic backups, and the staged deploy-rs updater work — probing, restoring, pausing, and rolling back.
when: Read when a Discord health alert fires, when restoring service state from the offsite repo, or when a staged fleet update deploys, defers, or rolls back.
resource: modules/deploy.nix
tags:
  [runbook, pi, alpha, epsilon, backups, restic, alerting, upgrades, deploy-rs]
---

# Fleet health, offsite backups, and auto-updates

The pi is the always-on controller. Three systems keep the fleet observable and
recoverable: fleet-health probes, an offsite restic repo, and a nightly staged
deploy-rs update. All three post to the `#notifications` Discord channel, and
the monitor posts directly rather than through the hermes container, so it
still reports when hermes itself is down.

## Fleet CLI and agent discovery

The generated `fleet` CLI is the operator-facing discovery and inspection
surface. Its command registry generates dispatch, help, and machine-readable
metadata from one Nix attrset:

```sh
fleet --help
fleet commands --json
```

Agents should use the
[fleet-operations skill](../../.agents/skills/fleet-operations/SKILL.md) for
runtime work and discover capabilities from `fleet commands --json` instead
of copying this command surface into prose. Configuration verification remains
a separate pre-activation procedure in `verify-nixos-config`.

`fleet update` delegates to the interactive `host-update` path for the local
tree. It is deliberately distinct from the controller-side `fleet-update`
transaction below, which deploys a main revision after successful CI.

## Fleet health (`fleet-health.timer`, every 5 min)

Probes every systemd unit that matters plus every HTTP surface across the
fleet: the pi and epsilon services (traefik, authelia, HA, hermes, glance, ASF,
and miniflux), the apex, rss, and paper vhosts, and alpha's published
backends (jellyfin, qbit, bazarr, prowlarr, radarr, sonarr, finance).

- Two consecutive failures post `DOWN name (detail)` as a new message;
  recovery deletes that message (no `UP` post — the channel only shows
  what is currently down). Single blips stay silent. If a DOWN message
  lingers after recovery, check `journalctl -u fleet-health.service` for
  `POST failed` / `DELETE failed` lines: a failed delete keeps the msgid
  file for retry on the next run.
- Oneshot units (restic) are judged by `systemctl is-failed`, not
  `is-active` — inactive between runs is healthy.
- State lives in `/var/lib/fleet-health/`. To re-arm an alert while
  debugging, delete the counter (and `.<check>.msgid`) for that check.
- A `PAUSE` flag on the updater (`/var/lib/auto-update/PAUSE`) raises an
  alert of its own, so paused automation never rots silently.

Pi also installs a type-wide systemd `service.d` failure hook. When any
service exhausts its configured restart policy and enters the failed state,
the hook starts the normal fleet probe immediately and again after 60 seconds.
Those two serialized passes use the same counters and Discord messages as the
timer, reducing persistent service-failure detection to about one minute
without bypassing the two-strike rule. Existing unit-specific `OnFailure=`
handlers are additive and continue to run. HTTP and cross-host failures still
rely on the periodic sweep because they do not emit local systemd failures.

## Offsite backups (`restic-backups-offsite.timer`, daily 01:00–01:15)

Restic over rclone to `gd-crypt:restic/<hostname>`. Covers:

- pi/epsilon: `/etc`, `/boot`, `/root`, the whole `/home/repparw`, container
  configuration and roots, NixOS account allocation state, timers and recovery
  metadata. Pi also includes deployment/health controller and Bluetooth/radio
  state; epsilon includes ddclient state. See the host declarations and
  `modules/aspects/backup.nix` for the complete paths and exclusions.
- alpha: `/home/containers/backup`, Pictures, Documents (Memorias excluded),
  and the small home-state allowlist in `modules/hosts/alpha.nix`. SQLite
  databases are exported with `.backup` into a private staging tree under
  `/var/lib/home-state-backup/offsite` before restic runs. Missing optional
  entries are skipped; an export failure aborts the backup. Age keys are
  included only in the HDD staging tree, never in the offsite tree.

Alpha's `rsync-job-bupstate` mirrors its separately prepared HDD staging tree
into `/mnt/hdd/backup/.config` and `.local`. It deletes destination entries
outside the allowlist, including legacy whole-`.config` contents and removed
sources. `rsync-job-buptohdd` handles Pictures and Documents separately and
protects those two state subtrees. Restore staged offsite state beneath the
user's home, rather than to its original `/var/lib` staging path.

Daily jobs exclude reproducible caches, container runtime mounts and swap.
Retention is 7d/4w/12m with a 5% data check each run. The pi/epsilon live backups are
not automatically consistent database exports.

For a full pi checkpoint, including the Nix store and a stopped-HA archive,
and a verified restore into a fresh directory, use the
[host recovery runbook](host-recovery.md). Never restore over live paths while
testing recovery. Backup scope changes apply after deployment.

Adding a new host's key to a secrets file:
`sops updatekeys --yes secrets/<file>.sops.yaml` from a machine that can
decrypt it.

## Staged auto-update

Lock maintenance runs in GitHub Actions; deployment runs on pi:

- `.github/workflows/lock-update.yml` runs daily at 04:15 UTC or through
  `workflow_dispatch`. It opens or refreshes `automation/flake-lock` as a PR.
  It never pushes main or activates a host.
- `fleet-deploy.timer` runs daily at 05:30 in the controller's timezone.
  It snapshots current `origin/main` and requires a successful push run of
  `ci.yml` for that exact commit before evaluation or activation.
  Missing, pending, failed, or unavailable CI results defer deployment without
  changing the rollback streak. The next scheduled run retries current main.
- Deployment proceeds through epsilon, pi, then alpha. Each host passes health
  checks before the next proceeds, including hosts already on that revision.
- `fleet-alpha-retry.timer` runs daily at 07:00 in the controller's timezone.
  It retries a deferred alpha against current main, with the same CI gate.

CI's host checks stub selected packages. Successful CI proves those checks,
not full system builds or runtime health. Real builds still run on targets
through deploy-rs; the controller still performs configuration evaluation.

### Enable lock update PRs

The lock workflow uses the built-in `GITHUB_TOKEN`. Its permissions are
Contents write for the lock branch, Pull requests write for the PR, and Actions
write for dispatching CI. No separate token or repository secret is needed.
The repository must allow GitHub Actions to create pull requests. Its current
`can_approve_pull_request_reviews` setting is enabled; the workflow never
approves or merges a PR.

Run `gh workflow run lock-update.yml` after this workflow and CI's
`workflow_dispatch` support reach main. GitHub requires the dispatched workflow
to exist on the default branch. Bot PR events are not the CI trigger this
workflow relies on; see [GitHub's workflow triggering rules](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

After publishing the lock branch and opening or updating its PR, the updater
explicitly dispatches `ci.yml` on `automation/flake-lock` with the expected head
SHA. Both CI jobs verify that SHA before checking out the event's immutable
`github.sha`. A branch change during dispatch fails that check rather than
validating a different commit.

An unchanged lock tree on the same main parent reuses the existing commit.
The updater checks for an existing dispatched run on that branch and SHA before
sending another dispatch. Concurrent dispatches for the same SHA share a CI
concurrency group, so only one remains active. GitHub indexing and dispatch are
not atomic: a recently accepted run may not be visible yet. An ambiguous
request failure is reported, and a retry checks GitHub before dispatching.
If an unchanged commit already has a failed or canceled run, rerun that CI run
explicitly after diagnosing it; the nightly updater does not repeat it.

Review the lock commit's dispatched `gate` and `persistence-vm` results before
merging. Bot PR events may also create approval-required runs; approving those
is unnecessary for the explicit dispatch and can start duplicate PR checks.
Deployment still requires a successful **push** CI run for the exact merged
main commit. A lock-branch dispatch, or even a manual dispatch on main, cannot
satisfy that separate deployment gate.

The lock workflow has its own concurrency group and one branch. Pi's pause
flag affects deployment only. Applying this configuration removes the old
`fleet-promote` service and timer; existing pause and rollback state remain.
Older controllers used rollback roots named by commit. After a verified full
rollout, inspect `/nix/var/nix/gcroots/fleet-update/` on each host and remove
obsolete commit roots. Keep `previous` while a rollout or recovery is pending.

Hosts with graphical sessions deploy only when every local session is idle
or locked — active use (including media streams) defers the host instead of
forcing it. A deferred alpha is reported, not failed.

Main records the desired revision. `/var/lib/auto-update/deployed-revision`
records the last revision verified across all hosts. A deferred alpha leaves
that value unchanged, and a rollback can leave hosts behind main.

Failure handling:

- Activation failures roll back via deploy-rs magic rollback.
- Before activation, the controller saves and roots each host's prior system.
  A deployment failure restores those exact systems on hosts reached during
  this revision, including a host whose activation command failed. The saved
  state also covers hosts reached in an earlier run before alpha was deferred.
  Rollback verifies the restored system path. An unsuccessful rollback pauses
  deployment and retains the roots for recovery. Deployment never writes Git.
  Each host has one `fleet-update/previous` root, replaced on its next
  activation attempt. After a successful rollback or full convergence, these
  roots are removed.
- Two consecutive failed cycles pause automation (`PAUSE` flag) and alert. A
  build or activation failure pauses on the first cycle instead: the same lock
  fails the same way, so a second attempt only spends a deploy cycle. Soak
  failures keep the two-strike rule, because a flapping container or a
  timed-out probe can clear before the next attempt.
- Boot-level regressions remain a rescue-console problem; re-imaging the pi
  from a cloned SD of the last known-good system is the final recovery path.

### Reading a deploy failure alert

The rollback alert carries the reason, so the alert is usually enough to
diagnose without reproducing the deploy. A build failure quotes the error:

````text
:rotating_light: fleet deployment failed at alpha (139e7d50); rollback
initiated, 2 consecutive — automation PAUSED (breaker)
```what failed
gamescope> FAILED: [code=1] layer/libVkLayer_..._wsi_x86_64.so.p/....o
gamescope> ../layer/VkLayer_FROG_gamescope_wsi.cpp:319:5: error: ...
```
````

A soak or gate failure names the probe or step instead, for example
`soak: container@jellyfin is activating on alpha`. Only one of the two ever
appears; the alert never restates the host the headline already names.

The full build and activation output is kept at
`/var/lib/auto-update/fail-<host>.log` on the pi, one file per host,
overwritten by the next deploy. It outlives the transient
`fleet-deploy-run` unit's journal, which does not survive a controller
reboot — a controller that rebooted mid-deploy leaves no unit entries to
read. Prefer that file over `journalctl -u fleet-deploy-run`.

Operator controls:

```sh
ssh root@192.168.0.4 'touch /var/lib/auto-update/PAUSE'       # pause automation
ssh root@192.168.0.4 'rm /var/lib/auto-update/PAUSE'          # resume automation
gh workflow run lock-update.yml                            # open a lock update PR
ssh root@192.168.0.4 'systemctl start fleet-deploy.service'   # launch fleet consumption
ssh root@192.168.0.4 'fleet-update deploy --host epsilon'     # consume main on one host
nix run .#deploy-rs -- .#epsilon --dry-activate               # test a local tree
```

A manual deploy takes the same serialization lock — without `--wait-lock`
it exits if a transaction is already running rather than interrupting it.
Alpha's interactive `Mod+U` asks the pi controller to run
`fleet-update deploy --host alpha --force`: it bypasses the activity gate
and `PAUSE` but keeps the exact-commit CI gate, health checks, and rollback. The separate
`host-update` command remains for building and reviewing a local tree by hand.

## Firmware updates (`fwupd`, hardware hosts)

`services.fwupd` is enabled on hosts with LVFS-discoverable devices (alpha,
beta). pi is an SD-boot SBC and epsilon a VPS — neither carries fwupd-managed
hardware. Firmware does not ride the flake: check and apply it by hand every
few weeks, or when the edge/dock hardware misbehaves.

```sh
ssh alpha 'fwupdmgr refresh'      # pull metadata from LVFS
ssh alpha 'fwupdmgr get-updates'  # list pending firmware
ssh alpha 'fwupdmgr update'       # stage; some devices only apply at reboot
```

Device firmware applies at the next reboot of the device or host — schedule
accordingly. UEFI capsule updates require the ESP mounted at `/boot` (alpha's
systemd-boot layout already satisfies this).

## Related

- [Deploy NixOS to the Raspberry Pi](deploy-pi-nixos.md)
- [Update rollback](update-rollback.md)
- [Troubleshooting](../troubleshooting.md)
