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
- Sessions live in `/var/lib/free-games-claimer/data` (host path
  `/home/containers/config/free-games-claimer/data`, included in the service
  backup export). No passwords are stored; logins are interactive and persist
  as browser cookies. The application runs directly from the immutable Nix store.
- New claims, errors, and login/captcha trouble post to the fleet Discord
  channel through the shared bot identity. The browser runs as `fgc`, without
  access to the bot token. A root-only post-stop notifier reads `hermes-env`.
  Notification batches only advance saved state after every post succeeds.
- Port 6080 is available only on the Pi host's loopback interface, through an
  SSH tunnel. Other containers and routed clients are blocked from accessing
  the noVNC endpoint directly.

## First login and re-login

1. From a desktop: `ssh -N -L 6080:127.0.0.1:6080 pi`
2. Open <http://localhost:6080/vnc.html?autoconnect=1&resize=scale>
3. Run the service so a browser opens:
   `ssh pi sudo -A systemctl -M free-games-claimer start free-games-claimer.service` (the run waits up to
   `LOGIN_TIMEOUT` = 10 minutes for the login).
4. Log in inside the VNC browser. Epic offers app OTP; GOG sends email codes.
   The session persists afterwards; repeat only when a store logs out.

Captcha notes: Epic can throw hcaptcha on login or claim. The pi's residential
IP plus the patchright evasions keep this rare; when it happens, solve it in
the VNC page while the run is still waiting, then rerun the service.

## Runbook

- Claim results and failures: `journalctl -M free-games-claimer -u free-games-claimer.service` on
  pi; per-store output is in
  `/home/containers/config/free-games-claimer/logs/<store>.log`.
- Manual run: `ssh pi sudo -A systemctl -M free-games-claimer start free-games-claimer.service`
- Dry run (no purchases): add `DRYRUN=1` to the unit environment temporarily.
- A failed run does not block the next day's timer; the notify state replays
  the report if Discord was unreachable. Generic execution failures are also
  reported, even when no claim database entry was created.

## Related

- [Service model](service-model.md)
- [Host profiles](../hosts.md)
- [Fleet health, backups, and deployment](../runbooks/fleet-operations.md)
