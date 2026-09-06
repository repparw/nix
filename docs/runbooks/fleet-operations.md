---
type: Runbook
title: Fleet health, offsite backups, and auto-updates
description: How fleet-health alerting, offsite restic backups, and the staged deploy-rs updater work — probing, restoring, pausing, and rolling back.
when: Read when a Discord health alert fires, when restoring service state from the offsite repo, or when a staged fleet update deploys, defers, or rolls back.
resource: modules/deploy.nix
tags: [runbook, pi, alpha, epsilon, backups, restic, alerting, upgrades, deploy-rs]
---

# Fleet health, offsite backups, and auto-updates

The pi is the always-on controller. Three systems keep the fleet observable and
recoverable: fleet-health probes, an offsite restic repo, and a nightly staged
deploy-rs update. All three post to the `#notifications` Discord
channel using the bot token from `hermes-env` — the monitor deliberately
does not go through the hermes container, so it still reports when hermes
itself is down.

## Fleet health (`fleet-health.timer`, every 5 min)

Probes every systemd unit that matters plus every HTTP surface across the
fleet: the pi and epsilon services (traefik, authelia, HA, hermes, glance, ASF,
and miniflux), the apex and rss vhosts, and alpha's published
backends (jellyfin, qbit, bazarr, prowlarr, radarr, sonarr, paperless,
finance).

- Two consecutive failures alert (`DOWN name (detail)`); recovery posts
  `UP name`. Single blips stay silent.
- Oneshot units (restic) are judged by `systemctl is-failed`, not
  `is-active` — inactive between runs is healthy.
- State lives in `/var/lib/fleet-health/`. To re-arm an alert while
  debugging, delete the counter (and `.alerted`) for that check.
- Adding a service = one line in
  `modules/aspects/services/fleet-health.nix` (unit or HTTP probe).

The probe doubles as a library for gates: `fleet-health-probe --strict
--local` exits nonzero on any failure and skips cross-host checks. The updater
also runs explicit per-node unit and HTTP gates during each soak. Monitoring
mode alerts once if
`/var/lib/auto-update/PAUSE` exists, so paused automation never rots
silently.

Probe gotcha: traefik sets `sniStrict = true`. curl takes SNI from the
URL, so HTTPS probes must use `--resolve host:443:127.0.0.1` — a bare
`-H "Host: ..."` fails the handshake with `tlsv1 unrecognized name`.

## Offsite backups (`restic-backups-offsite.timer`, daily 05:00)

Restic over rclone to `gd-crypt:restic/<hostname>` — a crypt remote over
gdrive only (the union's consumer-cloud legs filled up and 507'd; restic
chunks do not need triple-copy redundancy). Covers:

- pi: `/home/containers/config`, `/home/repparw/services/hass`,
  `/home/repparw/services/hermes`
- alpha: `/home/containers/backup`, Pictures, Documents (Raw/Memorias
  excluded — owner-managed; `.config` excluded — Firefox sync covers the
  browser, the rest is cache or regenerating state)

Retention 7d/4w/12m; 5% data check each run. The rclone config renders
at unit start from sops secret file contents into the unit's runtime dir
(rclone has no path indirection in config values — a static conf
referencing `/run/secrets` paths is read literally and fails). The crypt
password is stored rclone-obscured in `secrets/rclone.sops.yaml`.

Restore:

```sh
export RESTIC_PASSWORD_FILE=/run/secrets/resticPassword
restic -r rclone:gd-crypt:restic/pi -o rclone.program=$(which rclone) snapshots
restic -r rclone:gd-crypt:restic/pi -o rclone.program=$(which rclone) restore latest --target /tmp/restore
```

Adding a new host's key to a secrets file:
`sops updatekeys --yes secrets/<file>.sops.yaml` from a machine that can
decrypt it.

## Staged auto-update

Pi is the controller and sole lock writer, but publishing and deploying are
independent transactions. `fleet-promote.timer` runs daily at 04:15. It resets
a persistent checkout to exact `origin/main`, checks disk and current pi
health, takes a best-effort restic snapshot, bumps all inputs, and validates the
deploy schema plus all three host evaluations. If the lock changed, it commits
and pushes the candidate to GitHub, records its exact revision and parent, and
exits without changing a host. The GitLab mirror push is best-effort.

`fleet-deploy.timer` runs at 05:30 whether promotion succeeded or failed. It
fetches exact current `origin/main`, pre-evaluates every real deployment
profile before changing the canary, and deploys it with deploy-rs in
blast-radius order:
**epsilon → pi → alpha**. Every changed node is activated with deploy-rs magic
rollback enabled, then must pass two consecutive unit and HTTP health checks.
Hosts carrying `den.aspects.desktop` are deployed only when every local
graphical user session is idle, locked, or no longer active; otherwise they are
reported as deferred. Before accepting those session hints, the gate also
rejects any runtime systemd inhibitor whose mode is `block` and whose `what`
contains `sleep`. This catches active remote game and media streams even while
the physical session is locked. Delay-mode sleep inhibitors (including rtkit
and swayidle) and inhibitors for unrelated actions such as power-key handling
do not gate deployment. Pi's 07:00 `fleet-alpha-retry.timer` runs a
consumer-only retry against the current main revision, so the retry,
full-fleet pass, and interactive force command share one serialization lock.
Keeping this service on pi also avoids replacing an active update unit on
alpha during activation. The retry and force paths wait up to three hours for an
in-progress fleet transaction, then either converge alpha or recognize that it
is already current. A host that already runs the candidate is recognized as
converged before this activity gate.

The timer launches the long transaction as the transient
`fleet-deploy-run.service`. This keeps the declarative launcher inactive while
pi replaces its own system configuration and avoids a self-update systemd
transaction cycle.

deploy-rs owns closure builds and copies, activation, SSH confirmation,
dry-activation, and activation-failure rollback. The wrapper supplies only
fleet policy that deploy-rs does not: exact-main consumption, serial canary
ordering, desktop gating, application-health soaks, notifications, and
post-soak rollback. Activation and confirmation timeouts live in the deploy-rs
configuration rather than command-line overrides.

Invariant: **origin/main's flake.lock always equals the pin production
converged on.** Rollbacks push a revert commit; git log is the update
history.

Failure handling:

- Activation failures are handled first by deploy-rs magic rollback.
- A failed post-activation soak reverts main only when it still points at the
  recorded, bot-authored, flake-lock-only candidate. It never infers a
  candidate from `HEAD` or reverts a later manual commit. The consumer then
  redeploys the reverted graph to every persistently recorded node already
  reached. If that deploy fails, it switches the node back to its recorded
  pre-update profile.
- Two consecutive failed cycles trip the controller's breaker by creating its
  `PAUSE` flag and alerting.
- Boot-level regressions remain a rescue-console problem. Pi's rescue SD is the
  final recovery path for an unbootable generation.

Operator controls:

```sh
ssh root@192.168.0.4 'touch /var/lib/auto-update/PAUSE'       # pause automation
ssh root@192.168.0.4 'rm /var/lib/auto-update/PAUSE'          # resume automation
ssh root@192.168.0.4 'systemctl start fleet-promote.service'  # produce an update
ssh root@192.168.0.4 'systemctl start fleet-deploy.service'   # launch fleet consumption
ssh root@192.168.0.4 'fleet-update deploy --host epsilon'     # consume main on one host
nix run .#deploy-rs -- .#epsilon --dry-activate               # test a local tree
```

Alpha's interactive `Mod+U` asks pi's fleet controller to run
`fleet-update deploy --host alpha --force`. Because the user explicitly initiates it,
the command bypasses the desktop activity/inhibitor gate and automation
`PAUSE`. It still shares the controller's serialization lock, deploys the exact
current `origin/main` revision through deploy-rs, applies the health soak, and
rolls back a failed deployment. The separate `host-update` command remains
available when an operator specifically wants to build and review a local tree.

Controller artifacts live in `/var/lib/auto-update/`: the atomic `candidate`
record, `target-revision`, `deployed-revision`, `rollback-streak`, durable
`before-<revision>-<host>` / `reached-<revision>-<host>` rollback records, and
`diff-<host>.txt`. Alpha's retry uses that same controller state. A `PAUSE`
file pauses both scheduled transactions. Node success notifications attach the
closure diff; the final notification distinguishes full convergence from a
deferred alpha.

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
