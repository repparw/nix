---
type: Runbook
title: Free games claimer login recovery
description: Recover storefront sessions when unattended checkout cannot authenticate.
when: Read when the free-games claimer needs login, is challenged by a captcha, or loses its session.
resource: modules/aspects/services/free-games-claimer.nix
tags: [services, games, authentication, recovery]
---

# Free games claimer login recovery

The [service module](../../modules/aspects/services/free-games-claimer.nix) and
[package](../../modules/_packages/free-games-claimer.nix) own the store
selection, schedule, retries, browser mode, and logs. This page does not repeat
those details.

In live testing, Epic rejected headless Chromium with a Cloudflare challenge, so
it needs a temporary headed session. GOG can normally reuse a saved Chromium
profile in headless mode. Neither store requires storing account passwords in
Nix. Browser state persists outside the store and is included in the service's
backup scope.

When a session expires or a captcha appears, use SSH port forwarding to reach
the claimer's temporary VNC server, which listens only on loopback. Starting
the service changes live state, so obtain authorization first. Run these in
separate terminals:

```sh
ssh -N -L 5900:127.0.0.1:5900 pi
ssh -t pi sudo systemctl start --no-block free-games-claimer.service
nix shell nixpkgs#tigervnc -c vncviewer localhost:5900
```

Complete authentication in Chromium while the service runs. For GOG, enable the
service's `SHOW=1` mode temporarily before activation, so the browser is
visible. VNC is unavailable outside a running headed session. Do not expose its
port publicly or embed login credentials in the module.

To diagnose a failed run:

```sh
ssh pi journalctl -u free-games-claimer.service -n 100
ssh pi systemctl list-timers free-games-claimer.timer
```
