---
type: Runbook
title: Fleet health, offsite backups, and auto-updates
description: How the pi's fleet-health alerting, offsite restic backups, and nightly auto-update pipeline work — probing, restoring, pausing, and rolling back.
when: Read when a Discord health alert fires, when restoring service state from the offsite repo, or when pi flips or rolls back on its own and you need to pause or inspect automation.
resource: modules/aspects/services/fleet-health.nix
tags: [runbook, pi, alpha, backups, restic, alerting, upgrades]
---

# Fleet health, offsite backups, and auto-updates

The pi is the always-on host. Three systems keep it observable and
recoverable: fleet-health probes, an offsite restic repo, and a nightly
auto-update pipeline. All three post to the `#notifications` Discord
channel using the bot token from `hermes-env` — the monitor deliberately
does not go through the hermes container, so it still reports when hermes
itself is down.

## Fleet health (`fleet-health.timer`, every 5 min)

Probes every systemd unit that matters plus every HTTP surface on both
hosts: the pi edge (traefik, authelia, HA, hermes, glance, ASF, the
miniflux container), the apex and rss vhosts, and alpha's published
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
--local` exits nonzero on any failure and skips cross-host checks. The
auto-update job uses exactly that scope, so an unrelated alpha outage can
never gate or roll back pi. Monitoring mode also alerts once if
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

## Auto-update (strategy C, `auto-update.timer`, daily 04:15)

The nightly job runs unattended and replaces the old report-then-ssh-flip
flow. Pipeline: clone main → bump all inputs (skip silently if the lock
did not move) → GC if `/nix` is under 10G, abort-and-alert under 6G →
strict local probe of the current system → best-effort restic snapshot
(capped at 20 min) → build pi's closure → commit and push the bumped lock
to main via repparw's enrolled GitHub key (abort if the push fails; never
flip an unpushed tree) → `nixos-rebuild switch` → soak for up to ten
minutes against strict local probes.

Invariant: **origin/main's flake.lock always equals the pin production
converged on.** Rollbacks push a revert commit; git log is the update
history.

Failure handling:

- Soak failure → automatic `nixos-rebuild switch --rollback`, revert
  push, `ROLLED BACK` alert with the generation's diff attached.
- Two consecutive rollbacks trip the breaker: automation sets its own
  PAUSE flag and alerts.
- Boot-level regressions cannot self-heal — that is what the rescue SD is
  for. pi runs linuxPackages_latest with the `pcie_brcmstb` initrd module
  so stage-1 enumerates the NVMe; a cold power-cycle boot on latest is
  proven.

Operator controls:

```sh
ssh pi 'touch /var/lib/auto-update/PAUSE'   # pause automation
ssh pi 'rm /var/lib/auto-update/PAUSE'      # resume
ssh pi 'systemctl start auto-update.service' # force a cycle now
```

Artifacts: diff at `/var/lib/auto-update/diff.txt`, built closure at
`/var/lib/auto-update-result`, rollback streak in
`/var/lib/auto-update/rollback-streak`. Success posts a classified
summary (`pi flipped — N packages changed (kernel)`) with the full diff
attached as a file.

## Related

- [Deploy NixOS to the Raspberry Pi](deploy-pi-nixos.md)
- [Failed auto-upgrade rollback](failed-auto-upgrade-rollback.md)
