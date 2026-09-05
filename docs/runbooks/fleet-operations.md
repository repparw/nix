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

## Staged auto-update (`auto-update.timer`, daily 04:15)

Pi is the controller and sole lock writer. Its `fleet-update --update-lock`
cycle resets a persistent checkout to `origin/main`, checks disk and current pi
health, takes a best-effort restic snapshot, bumps all inputs, and validates the
deploy schema plus all three host evaluations. If the lock changed, it commits
and pushes the candidate to GitHub before changing any host; the GitLab mirror
push is best-effort.

The candidate is then deployed with deploy-rs in blast-radius order:
**epsilon → pi → alpha**. Every changed node is activated with deploy-rs magic
rollback enabled, then must pass two consecutive unit and HTTP health checks.
Alpha is deployed only when its graphical session is idle, locked, or no
longer active; otherwise it is reported as deferred. The gate reads logind's
idle, lock, and session-state hints rather than depending on the graphical
locker implementation. Its 05:30 `alpha-auto-update.timer` is a consumer-only
retry against the current main revision. An alpha that already runs the
candidate is recognized as converged before this activity gate.

Invariant: **origin/main's flake.lock always equals the pin production
converged on.** Rollbacks push a revert commit; git log is the update
history.

Failure handling:

- Activation failures are handled first by deploy-rs magic rollback.
- A failed post-activation soak reverts the candidate commit on main and
  redeploys the reverted graph to every node already reached. If that deploy
  fails, the updater switches the node back to its exact pre-update profile.
- Two consecutive failed cycles trip the controller's breaker by creating its
  `PAUSE` flag and alerting.
- Boot-level regressions remain a rescue-console problem. Pi's rescue SD is the
  final recovery path for an unbootable generation.

Operator controls:

```sh
ssh root@192.168.0.4 'touch /var/lib/auto-update/PAUSE'    # pause writer
ssh root@192.168.0.4 'rm /var/lib/auto-update/PAUSE'       # resume writer
ssh root@192.168.0.4 'systemctl start auto-update.service' # force a cycle
nix run .#fleet-update -- --host epsilon                    # converge one node
nix run .#fleet-update -- --host epsilon --dry-activate     # activation test
```

Controller artifacts live in `/var/lib/auto-update/`: `candidate-revision`,
`deployed-revision`, `rollback-streak`, and `diff-<host>.txt`. Alpha's retry
uses `/var/lib/alpha-auto-update/`. A `PAUSE` file is scoped to that job. Node
success notifications attach the closure diff; the final notification
distinguishes full convergence from a deferred alpha.

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
