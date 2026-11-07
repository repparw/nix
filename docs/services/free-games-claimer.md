---
type: Runbook
title: Free games claimer
description: Automated checkout of Epic and GOG free games on Pi.
when: Read when claiming fails, a login is needed, or the free-games feed changes.
resource: modules/aspects/services/free-games-claimer.nix
tags: [services, games, discord]
---

# Free games claimer

Pi checks Epic and GOG daily at 18:10 ART (with up to 30 minutes of jitter).
Steam stays on ASF + FreePackages on epsilon; the freestuff bot can keep
announcing itch.io, Humble, and other stores, with Steam/Epic/GOG excluded.

The [FroggMaster fork](https://github.com/FroggMaster/free-games-claimer)
is packaged in `modules/_packages/free-games-claimer.nix` and uses Nixpkgs
Chromium. A sandboxed systemd service runs native headless Chromium by default.
Xvfb and loopback-only VNC start only when SHOW=1 is selected for headed
recovery. No display or VNC process runs during normal claims.

Cookies and claim databases are stored in
`/home/containers/config/free-games-claimer/data`, included in the existing
service backup. No store passwords are stored. The browser does not have
access to the Discord bot token; a privileged post-stop notifier reads
`hermes-env` and tracks which results have been announced. Failed
notifications are retried on the next run.

## Headless trial, login and recovery

Regular runs use the saved Chromium profile with SHOW=0. If a saved session
has expired, the script fails without waiting for unattended terminal prompts.
The actual Pi session and storefront checkout still need a live smoke test.
If headless mode causes captchas, revert the service's SHOW setting to 1.

For first login or recovery, set SHOW=1 in the systemd service environment and
deploy that change. This restores the former Xvfb and VNC behavior.

Use three terminals on your desktop:

1. Forward Pi's loopback-only VNC port:
   `ssh -N -L 5900:127.0.0.1:5900 pi`
2. Start the claimer without blocking the SSH session:
   `ssh -t pi sudo systemctl start --no-block free-games-claimer.service`
3. Connect while the service is running, for example on NixOS:
   `nix shell nixpkgs#tigervnc -c vncviewer localhost:5900`

Log in through the Chromium window. Epic may require an authenticator code,
and GOG may send an email code. The login timeout is 10 minutes per store.
If a captcha occurs later, repeat these steps during that run. The VNC
endpoint is only available while the service is active, and only over SSH.

## Operations

- Run now: `ssh -t pi sudo systemctl start free-games-claimer.service`
- Check service output: `ssh pi journalctl -u free-games-claimer.service -n 100`
- Check individual logs: `/home/containers/config/free-games-claimer/logs/epic-games.log`
  and `gog.log` on Pi.
- Inspect schedule: `ssh pi systemctl list-timers free-games-claimer.timer`
- Test without purchases: temporarily set `DRYRUN=1` in the service environment.

The timer runs daily at 18:10 ART plus up to 30 minutes of jitter. Exit 75
marks a recognized temporary checkout failure and triggers a retry after
45 minutes. Systemd permits at most four starts (including manual starts) in
a rolling 23-hour window, so at most three retries follow a scheduled start.
Unexpected exceptions, authentication errors and detected captchas exit 1
without automatic retries. The next daily timer attempts the claims again,
subject to systemd's start limit. The Discord notifier remains in this
experiment; switching to Grafana-only alerts is a separate change.

## Related

- [Service model](service-model.md)
- [Host profiles](../hosts.md)
- [Fleet operations](../runbooks/fleet-operations.md)
