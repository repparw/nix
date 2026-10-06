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

Pi also collects `fleet-unit-snapshot` over root SSH from alpha and epsilon,
using their configured service addresses and the existing deployment key. Unit
alerts include the remote hostname, so identically named units remain separate.
`host-units:<host>` means the snapshot could not be read (including an SSH
outage), rather than that the host has recovered. Existing unit alerts and the
last successful snapshot stay intact until that host can be inspected again.
`--local` skips these SSH sweeps; `--strict` keeps the existing deployment probe
behavior and does not change failed-unit alert state.

All three hosts retain failed offsite backup results; alpha additionally
retains Btrfs-health/scrub, Jellyfin-backup, and configured rsync job results.
`ExecStopPost` records failed runs in `/var/lib/fleet-unit-state/<unit>` and
removes that record only after a successful rerun. Each record contains a
timestamp and systemd's service result. The directory persists across reboot on the current roots and is declared for
`/persist` when host persistence is enabled, so `systemctl reset-failed` does not
make an unsuccessful backup look recovered. This is evidence of the most
recent observed failure, not proof of a fresh or restorable backup: jobs that
have never run and failures before installing the hook have no retained record.

Roll out the snapshot/recording aspect on alpha and epsilon before activating
the Pi controller change. Until a remote collector is installed, Pi reports
that host's snapshot as unavailable. To inspect retained evidence on a host:

```sh
sudo fleet-unit-snapshot
sudo ls -l /var/lib/fleet-unit-state
sudo cat /var/lib/fleet-unit-state/jellyfin-backup.service
```

Repair and rerun the underlying job to recover its alert. Removing evidence
manually only acknowledges the failure; it does not establish backup success.

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
  `workflow_dispatch`. It opens or refreshes `automation/flake-lock`, explicitly
  dispatches `ci.yml` for that exact lock commit, and auto-merges only when the
  candidate is still lock-only and `main` has not moved. It then explicitly
  dispatches CI for the exact resulting `main` revision. It never activates a
  host.
- `fleet-deploy.timer` runs daily at 05:30 in the controller's timezone.
  It snapshots current `origin/main` and requires a successful exact-SHA
  `ci.yml` run on `main`, either from a normal push or the updater's guarded
  `workflow_dispatch`, before evaluation or activation. Missing, pending,
  failed, or unavailable CI results defer deployment without changing the
  rollback streak. The next scheduled run retries current main.
- Preparation captures the same immutable Git revision for every selected
  host, evaluates each configuration sequentially, then builds and pins each
  deploy-rs profile on its target. It verifies the built system's revision
  before any activation starts. A failed preparation pauses automation without
  activating or rolling back a host.
- Activation attempts epsilon, alpha, then pi using the captured profiles.
  Alpha can be deferred by the
  activity gate; Pi reports its snapshot as unavailable until its collector is
  installed. For the initial collector rollout, use an authorized
  `--host all --force` deployment or activate both remote hosts first. Each
  activated host passes health checks before the next proceeds, including hosts
  already on that revision.
- `fleet-alpha-retry.timer` runs daily at 07:00 in the controller's timezone.
  It retries a deferred alpha against current main, with the same CI gate.

CI's host checks stub selected packages. Successful CI proves those checks,
not full system builds or runtime health. The controller evaluates each host
once and sends its derivation graph to that target. Targets build their own
closures and retain one `fleet-update/prepared` GC root. Deploy-rs activates
the captured derivations, which are already built, with its existing magic
rollback and confirmation protocol. Activation does not evaluate host modules
again or resolve a newer main revision.
The controller retains one `fleet-update/derivation-<host>` root per selected
host so garbage collection cannot discard captured build inputs before
activation. The next preparation replaces these roots.

Read `/var/lib/auto-update/latest-preparation` for the current evidence
directory. Each invocation retains captured host metadata, capture and preparation logs,
and a result containing the host, revision, system path, profile path, and
outcome. Every selected host has a result before capture starts, with null paths
until metadata is available. Capture failures record `failed` with `stage: capture`.
`not_attempted` means target preparation did not start for that host. A failed
revision check retains the revision returned by the built system.

The 2026-10-03 capacity inspection found 4 CPUs and 8 GiB RAM on Pi,
12 CPUs and 64 GiB RAM on Alpha, and 2 CPUs and 12 GiB RAM on Epsilon.
Pi had 12 GiB free on `/nix`; Epsilon had 104 GiB free. Sequential evaluation
keeps Pi from evaluating three systems concurrently. Native target builds
avoid storing Alpha's system closure on Pi and avoid cross compilation.
This design uses the existing substituters and needs no shared binary cache.

Lightweight checks, shared configuration checks, and each host's stubbed
evaluation run in parallel. The required `gate` waits for every group and the
disposable persistence VM test; a failed, skipped, or cancelled dependency
fails the gate. Each job uploads individual check logs and records durations
in its summary. Superseded PR runs are cancelled, while main push runs retain
separate concurrency groups so the deployment controller can verify its
captured revision. Explicit lock-update dispatches remain deduplicated by
workflow SHA and expected SHA, with the expected SHA verified before checkout
in every build job.

### Enable lock update PRs

The lock workflow uses the built-in `GITHUB_TOKEN`. Its permissions are
Contents write for the lock branch, Pull requests write for the PR, and Actions
write for dispatching CI. No separate token or repository secret is needed.
The repository must allow GitHub Actions to create pull requests and update
`main`. No approval is synthesized: after exact candidate CI succeeds, the
workflow creates a merge commit whose first parent is the validated main SHA and
whose second parent is the validated lock PR head. It publishes that commit with
a lease pinned to the original main SHA, so checking the base and updating main
are one compare-and-swap operation.

Run `gh workflow run lock-update.yml` after this workflow and CI's
`workflow_dispatch` support reach main. GitHub requires the dispatched workflow
to exist on the default branch. Bot PR events are not the CI trigger this
workflow relies on; see [GitHub's workflow triggering rules](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

After publishing the lock branch and opening or updating its PR, the updater
explicitly dispatches `ci.yml` on `automation/flake-lock` with the expected head
SHA. Every CI job verifies that SHA before checking out the event's immutable
`github.sha`. A branch change during dispatch fails that check rather than
validating a different commit. Lock-only PR events are ignored to avoid the
approval-required duplicate run produced for bot-authored PRs.

An unchanged lock tree on the same main parent reuses the existing commit.
The updater checks for an existing dispatched run on that branch and SHA before
sending another dispatch. Concurrent dispatches for the same SHA share a CI
concurrency group, so only one remains active. GitHub indexing and dispatch are
not atomic: a recently accepted run may not be visible yet. An ambiguous
request failure is reported, and a retry checks GitHub before dispatching.
If an unchanged commit already has a failed or canceled run, rerun that CI run
explicitly after diagnosing it; the nightly updater does not repeat it.

A successful lock-branch gate is the merge condition. The final publication is
an atomic compare-and-swap: if `main` changes after validation but before the
push, the lease rejects the merge and the PR remains for the next refresh. The
merge commit retains the validated PR head as a parent, so GitHub can recognize
the PR as merged without a separate non-atomic merge API call.

Immediately after a successful publication, the updater dispatches `ci.yml` on
`main` with the exact merged SHA and waits for that run as well. This explicit
post-merge dispatch is required because a `GITHUB_TOKEN`-authored push does not
reliably emit another workflow. Pi accepts either a successful push CI or this
guarded main dispatch, but only when its branch and head SHA exactly match the
revision being deployed. PR runs and lock-branch dispatches never satisfy the
deployment gate.

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
An authorized manual whole-fleet rollout can use
`fleet-update deploy --host all --force`. Force requires an explicit `--host`;
it bypasses the activity and pause gates while preserving the PAUSE file.
It keeps the exact-main push CI gate, serialization, health checks, and rollback.

Alpha's interactive `Mod+U` asks the pi controller to run
`fleet-update deploy --host alpha --force`: it bypasses the activity gate
and `PAUSE` but keeps the exact-commit CI gate, health checks, and rollback. The separate
`host-update` command remains for building and reviewing a local tree by hand.

## Pi store retention

Pi's 40 GB `/nix` filesystem uses daily GC. Before collecting unrooted paths,
`pi-generation-retention` keeps the newest five system profile generations,
the selected profile, and any generation whose closure contains the running
or booted system. This also handles deploy-rs profiles that wrap a NixOS system.
Missing runtime GC roots or a failed closure query abort cleanup before pruning.

The retention command holds `/run/fleet-update.lock` across pruning and GC. It
defers if a deployment or headless reboot sequence owns the lock. It changes
only system-profile generation links. User profiles, preparation roots under
`/var/lib/fleet-verify`, and `/nix/var/nix/gcroots/fleet-update/previous` remain
intact. Old preparation roots require a separate reviewed cleanup after the
corresponding rollout and rollback window have finished.

Preview eligibility without deleting generations or collecting store paths:

```sh
ssh root@192.168.0.4 'pi-generation-retention plan'
```

An authorized manual cleanup uses `pi-generation-retention apply`, or starts
`nix-gc.service`. Avoid `nix-collect-garbage -d`: it bypasses this generation
policy. Retaining five recent generations bounds ordinary profile history,
but cannot impose a byte limit on required systems or separately rooted
builds. Continue checking `df -h /nix`; the deployment preflight still requires
6 GiB free. Pi's automatic Nix GC also keeps its existing 3 GiB `min-free`
setting and never deletes profile generations itself.

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
