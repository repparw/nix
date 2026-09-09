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
deploy-rs update. All three post to the `#notifications` Discord channel, and
the monitor posts directly rather than through the hermes container, so it
still reports when hermes itself is down.

## Fleet health (`fleet-health.timer`, every 5 min)

Probes every systemd unit that matters plus every HTTP surface across the
fleet: the pi and epsilon services (traefik, authelia, HA, hermes, glance, ASF,
and miniflux), the apex and rss vhosts, and alpha's published
backends (jellyfin, qbit, bazarr, prowlarr, radarr, sonarr, paperless,
finance).

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

## Offsite backups (`restic-backups-offsite.timer`, daily 05:00)

Restic over rclone to `gd-crypt:restic/<hostname>`. Covers:

- pi: `/home/containers/config`, `/home/repparw/services/hass`,
  `/home/repparw/services/hermes`
- alpha: `/home/containers/backup`, Pictures, Documents (Raw/Memorias,
  `.config`, and browser state excluded)

Retention 7d/4w/12m; 5% data check each run.

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

Promotion and deployment are independent transactions, both serialized on
the pi:

- `fleet-promote.timer` (daily 04:15) bumps all inputs and pushes the new
  lock as a candidate commit. It changes no host.
- `fleet-deploy.timer` (daily 05:30) consumes current `origin/main` in
  blast-radius order: **epsilon → pi → alpha**. Each changed node soaks on
  health checks before the next proceeds.
- `fleet-alpha-retry.timer` (daily 07:00) retries a deferred alpha against
  current main.

Hosts with graphical sessions deploy only when every local session is idle
or locked — active use (including media streams) defers the host instead of
forcing it. A deferred alpha is reported, not failed.

Invariant: **origin/main's flake.lock is always the pin production converged
on.** Rollbacks push a revert commit; git log is the update history. Manual
commits are never auto-reverted.

Failure handling:

- Activation failures roll back via deploy-rs magic rollback.
- A failed post-activation soak reverts the candidate and redeploys the
  previous graph to every node already reached.
- Two consecutive failed cycles pause automation (`PAUSE` flag) and alert.
- Boot-level regressions remain a rescue-console problem; re-imaging the pi
  from a cloned SD of the last known-good system is the final recovery path.

Operator controls:

```sh
ssh root@192.168.0.4 'touch /var/lib/auto-update/PAUSE'       # pause automation
ssh root@192.168.0.4 'rm /var/lib/auto-update/PAUSE'          # resume automation
ssh root@192.168.0.4 'systemctl start fleet-promote.service'  # produce an update
ssh root@192.168.0.4 'systemctl start fleet-deploy.service'   # launch fleet consumption
ssh root@192.168.0.4 'fleet-update deploy --host epsilon'     # consume main on one host
nix run .#deploy-rs -- .#epsilon --dry-activate               # test a local tree
```

A manual deploy takes the same serialization lock — without `--wait-lock`
it exits if a transaction is already running rather than interrupting it.
Alpha's interactive `Mod+U` asks the pi controller to run
`fleet-update deploy --host alpha --force`: it bypasses the activity gate
and `PAUSE` but keeps the health soak and rollback. The separate
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
