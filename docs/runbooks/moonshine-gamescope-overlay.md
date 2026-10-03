---
type: Runbook
title: Moonshine HDR Gamescope streaming
description: Reproduce and verify the HDR streaming path, and why the Steam overlay is not part of it.
when: Debugging or changing Moonshine, Gamescope WSI, or HDR streaming on alpha.
resource: modules/aspects/streaming.nix
tags: [moonshine, moonlight, gamescope, steam, hdr, gaming]
---

# Moonshine HDR Gamescope streaming

Moonshine captures one stable HDR surface from Steam by running it inside a
nested Gamescope compositor. Do not re-enable Moonshine's own WSI layer around
that compositor; Gamescope has to own the surface Moonshine sees.

## No Steam overlay

The Steam overlay does not composite with `gamescope-wsi`, which HDR requires.
This is upstream [ValveSoftware/gamescope#1537], open since 2024-09-20 and
unfixed. Shift+Tab will not open the overlay in this path. Do not spend time
re-diagnosing it.

A local patch used to carry a proof of concept for that issue. It was dropped on
2026-09-29 because it bought a working overlay in only one of five tested
configurations, and because it used line-number-only patch hunks with no
context: any Gamescope release that shifted a line made the patch apply at the
wrong offset and fail to compile rather than fail to apply. It broke the fleet
for five consecutive nights before that was diagnosed, blocking a nixpkgs bump
each time. If a future Gamescope or nixpkgs bump reintroduces it, pin the
derivation and assert its version rather than carrying a context-free patch
against a rolling input.

`gamescope-wsi` is still required for HDR. Dropping the overlay patch did not
change that; `gamescopeHdr` is `pkgs.gamescope.override { enableWsi = true; }`
with no local patches, so a Gamescope bump now either builds or fails cleanly.

## Desktop stream launcher

The `Desktop` application boots a nested niri inside Moonshine's isolated
compositor (`modules/aspects/streaming.nix`: `moonshine-desktop`). Vicinae
cannot serve that session: its daemon is bound to the login session's
display, so `Mod+Space` in the stream would open the launcher on the
physical monitor at home, invisible to the client.

Instead the wrapper keeps a daemon-less `fuzzel` open whenever the streamed
workspace is empty (auto-open on connect, reopen after the last window
closes). It is already focused, so typing filters immediately with no Mod
key -- the phone-friendly path. `fuzzel`'s terminal for console entries is
pinned in `modules/aspects/gui/niri.nix` (`fuzzel/fuzzel.ini`), because the
stream has no `$TERMINAL`.

## Known-good settings

Persona 3 Reload on `alpha`, confirmed 2026-09-08 with Moonshine 0.15.0 and
Gamescope 3.16.28:

```ini
ResolutionSizeX=1920
ResolutionSizeY=1080
FullscreenMode=0
PreferredFullscreenMode=0
FrameRateLimit=60.000000
```

The working Gamescope invocation, with a 4K output and a 1080p game:

```sh
gamescope --steam -f -b -W 3840 -H 2160 -w 3840 -h 2160 -r 60 \
  --hdr-enabled -- bwrap --dev-bind / / \
  --tmpfs /mnt/seagate --tmpfs /home/containers/media/seagate -- \
  steam -tenfoot
```

`bwrap` stays inside Gamescope. Gamescope creates Xwayland outside the user
namespace; inside bwrap's namespace the root-owned `/tmp/.X11-unix` looks owned
by `nobody`, which wlroots rejects with a segfault. The sandbox exists to mask
the Seagate automounts, which Steam otherwise stats at startup and Proton maps
as DOS drives.

Required in the game process: `ENABLE_GAMESCOPE_WSI=1` and
`ENABLE_VK_LAYER_VALVE_steam_overlay_1=1`, with `DISABLE_MOONSHINE_WSI=1` set.
Do not set `PROTON_ENABLE_WAYLAND`; it belongs to a native Wine-Wayland
experiment that was tried on 2026-09-17 and abandoned the same day.

## Verify after a change

Before switching:

1. The generated Moonshine config contains the `Steam Big Picture HDR`
   application and no separate SDR Steam entry.
2. The Gamescope derivation enables its WSI layer
   (`pkgs.gamescope.override { enableWsi = true; }`) and lists no local
   patches.
3. The HDR launcher sets `DISABLE_MOONSHINE_WSI=1`, unsets
   `DISABLE_GAMESCOPE_WSI`, does not set `PROTON_ENABLE_WAYLAND`, and launches
   Gamescope with `--hdr-enabled`.
4. In a live game, `/proc/$game_pid/environ` contains `ENABLE_GAMESCOPE_WSI=1`
   and `ENABLE_VK_LAYER_VALVE_steam_overlay_1=1`.
5. The stream is HDR end to end. Shift+Tab opening the overlay is not a valid
   check on this path.
