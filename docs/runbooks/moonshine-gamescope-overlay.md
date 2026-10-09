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

Instead the wrapper keeps a daemon-less `fuzzel` open whenever the nested
compositor has no windows (auto-open on connect, reopen after the last window
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

## Game frame-time logging

The Moonshine Steam launcher enables MangoHud logging inside games. It keeps
the HUD hidden and leaves Gamescope and the Moonshine compositor unwrapped.
Steam, steamwebhelper and Heroic are blacklisted; child games inherit the
logger configuration. Both 64-bit and 32-bit MangoHud libraries carry the
small workaround for [MangoHud #1782](https://github.com/flightlessmango/MangoHud/issues/1782),
which otherwise prevents automatic logging while the HUD is hidden.

Logging starts one second after the game's rendering hook initializes and
records every presented frame until the game exits or logging is toggled off.
There is no frame cap configured by the logger. CSVs are written under
`~/.local/state/moonshine/frame-times`. At session launch, logs older than
seven days are removed, then the oldest logs are removed until the directory
is at most 256 MiB. A running capture can exceed that retention target.
MangoHud also retains samples in the game process for its summary; memory use
grows with capture length.

These timings observe game presentation through MangoHud's Vulkan/OpenGL
hooks. They do not measure encoded stream delivery, client pacing, or the
game engine's simulation time. Functional verification uses a small renderer;
it does not establish zero overhead in every game. Check a game CSV and HDR
after changing the launcher, and compare equivalent game scenes before
attributing a performance difference to logging.
