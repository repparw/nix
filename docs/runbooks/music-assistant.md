---
type: Runbook
title: Music Assistant
description: Operating, validating and troubleshooting the Music Assistant deployment on the Pi and the Sendspin client on Alpha.
when: Read when operating, troubleshooting or extending the Music Assistant setup.
resource: modules/aspects/services/music-assistant.nix
tags: [music, music-assistant, spotify, sendspin, home-assistant]
---

# Music Assistant runbook

## Architecture

- **Server:** Music Assistant runs natively (systemd service, not a container)
  on the **Pi** (`modules/aspects/services/music-assistant.nix`). It has an
  independent lifecycle from the Home Assistant nspawn container on the same
  host: restarting HA does not interrupt music.
- **State:** `/var/lib/music-assistant` on the Pi — in the impermanence
  persistence list and the backup set.
- **Alpha playback:** a persistent **Sendspin client** (`sendspin-client`
  aspect) connects to MA's Sendspin server (`ws://pi:8927/sendspin`) and
  outputs through PipeWire. It exposes MPRIS, so playerctl and media keys
  work. Playback lives in the MA server: closing a control frontend never
  interrupts it.
- **Home Assistant:** the `music_assistant` integration is declared in the HA
  container's `extraComponents`; it auto-discovers the MA server and exposes
  each MA player as a HA `media_player`.
- **Frontend:** MA's own web UI on port 8095 (PWA-capable). `Mod+M` still
  launches cliamp until the MA frontend workflow is validated.

## Providers

Enabled via `services.music-assistant.providers` in the aspect:

- `spotify` — library, playlists, search. Authenticated with the repo's
  Spotify OAuth client id (sops secret
  `musicAssistantSpotifyClientId`, injected as
  `MASS_APP_VAR_SPOTIFY_CLIENT_ID`). The OAuth refresh token is stored in
  MA's state directory after a one-time browser authorization.
- `spotify_connect` — permanently advertises MA as a Spotify Connect device
  (go-librespot) and discovers external Connect devices (phones, TV clients)
  as players.
- `sendspin` / `sendspin_source` — the Sendspin server that the Alpha client
  (and future endpoints) connect to.
- `chromecast`, `dlna`, `airplay` — LAN device discovery (TV, speakers).
- `hass` / `hass_players` — Home Assistant as music source and HA media
  players as MA targets. Requires a HA long-lived access token entered in
  MA's UI.
- `squeezelite` — Slimproto server for the planned Squeezelite-ESP32
  endpoints (see `docs/research/multi-room-audio-music-assistant-setup.md`).
- `ytmusic` — YouTube Music. Requires interactive authentication on first
  run and `deno` on PATH (the NixOS module adds it).

## Validation checklist

1. `systemctl status music-assistant` on the Pi — active, no failed units.
2. Web UI reachable: `http://<pi>:8095` (LAN) and `http://localhost:8095`
   through `ssh -L 8095:127.0.0.1:8095 pi`.
3. Spotify search returns tracks (initial library sync takes a while).
4. `sendspin daemon` client on Alpha shows up as an MA player and plays
   through PipeWire.
5. Closing/reopening the frontend never interrupts playback (playback is
   server-side).
6. Spotify app shows the MA device under Connect devices.
7. HA shows `media_player` entities for MA players after HA restart.
8. State survives reboot: `/var/lib/music-assistant` persists.

## Troubleshooting

- **Provider fails with "No module named ..."** — the provider dependency
  packages live in `pythonPath` of the overridden package, not the package
  itself. The declarative module handles this; for manual test runs use
  `nix eval .#nixosConfigurations.pi.config.services.music-assistant.package.pythonPath`.
- **LAN players not discovered** — mDNS (UDP 5353) and SSDP (UDP 1900, both
  directions) must reach the Pi from the LAN. The NixOS firewall default
  drops these; check `nft list ruleset`.
- **Spotify Connect device not visible from phones** — go-librespot listens
  on an ephemeral TCP port; `openFirewall` opens the ephemeral range.
- **Sendspin client handshake 404** — the URL must include the fixed
  `/sendspin` path.

## Pi native build (deferred)

The overridden MA package builds natively on the Pi; the only missing piece is
the **nodejs-slim 24.22.1 aarch64 substitute** (needed by the ytmusic dep
chain: azurite → furo-web → bgutil-ytdlp-pot-provider → yt-dlp-ejs). Its
~6 GB compile scratch does not fit `/nix` alongside the deployed system.
Resume when the substitute lands on cache.nixos.org:

```sh
ssh root@192.168.0.4   # then on the Pi:
cd /persist/ma-pr-build   # PR branch archive (re-copy with git archive if stale)
PKGDRV=$(nix eval --raw .#nixosConfigurations.pi.config.services.music-assistant.package.drvPath)
nix build "$PKGDRV^out" --no-link -o /persist/gc-roots/ma-pr-package \
  --option min-free 4G --option max-free 8G
```

Check substitute availability first with
`nix build /nix/store/<nodejs-slim-drv>^out --dry-run` from the failed log
(`/persist/ma-pkg-build.log`).
