---
type: Runbook
title: Free games claimer
description: Automated checkout of Epic and GOG free games on pi, replacing the Discord #free feed.
when: Read when the claimer fails, a store login is needed, or the free-games feed changes.
resource: modules/aspects/services/free-games-claimer.nix
tags: [services, containers, games, discord]
---

# Free games claimer

`containers.free-games-claimer` on pi claims free games so the fleet no longer
needs the freestuff Discord bot's `#free` channel:

| Store                 | Covered by                   | Notes                                                                                                                                                |
| --------------------- | ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Steam                 | ASF + FreePackages (epsilon) | Existing bot; unchanged.                                                                                                                             |
| Epic Games            | free-games-claimer           | Weekly games; daily claim run.                                                                                                                       |
| GOG                   | free-games-claimer           | Giveaway every few weeks; daily claim run.                                                                                                           |
| itch.io, Humble, misc | freestuff bot (filtered)     | No claim automation exists; keep the Discord bot but set its channel filters to exclude Steam/Epic/GOG so only the leftovers it can announce remain. |

Upstream: [FroggMaster/free-games-claimer](https://github.com/FroggMaster/free-games-claimer),
pinned in `modules/_packages/free-games-claimer.nix` (an active fork of
vogler/free-games-claimer carrying the patchright migration). The package
routes the browser to Nixpkgs Chromium via `FGC_CHROME_PATH` because branded
Chrome has no aarch64 Linux build.

## Runtime shape

- Daily timer at 18:10 ART (21:10 UTC, after Epic's 16:00 UTC Friday rotation)
  runs `epic-games` and `gog` against a permanent Xvfb display. Headless mode
  trips captchas, so the browser is always headed inside the virtual display.
- Sessions live in `/var/lib/free-games-claimer/app/data` (host path
  `/home/containers/config/free-games-claimer`, included in the service backup
  export). No credentials are stored; logins are interactive and persist as
  browser cookies.
- New `claimed`/`failed` results and login/captcha trouble post to the fleet
  Discord channel through the shared bot identity (`discord-notify` +
  `hermes-env`).

## First login and re-login

1. From a desktop: `ssh -N -L 6080:127.0.0.1:6080 pi`
2. Open <http://localhost:6080/vnc.html?autoconnect=1&resize=scale>
3. Run the service so a browser opens:
   `ssh pi sudo -A systemctl start free-games-claimer` (the run waits up to
   `LOGIN_TIMEOUT` = 10 minutes for the login).
4. Log in inside the VNC browser. Epic offers app OTP; GOG sends email codes.
   The session persists afterwards; repeat only when a store logs out.

Captcha notes: Epic can throw hcaptcha on login or claim. The pi's residential
IP plus the patchright evasions keep this rare; when it happens, solve it in
the VNC page while the run is still waiting, then rerun the service.

## Runbook

- Claim results and failures: `journalctl -u container@free-games-claimer` on
  pi; per-store output is in
  `/home/containers/config/free-games-claimer/logs/<store>.log`.
- Manual run: `ssh pi sudo -A systemctl start free-games-claimer`
- Dry run (no purchases): add `DRYRUN=1` to the unit environment temporarily.
- A failed run does not block the next day's timer; the notify state replays
  the report if Discord was unreachable.

## Related

- [Service model](service-model.md)
- [Host profiles](../hosts.md)
- [Fleet health, backups, and deployment](../runbooks/fleet-operations.md)
