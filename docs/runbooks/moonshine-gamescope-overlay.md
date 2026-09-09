---
type: Runbook
title: Moonshine HDR Gamescope Steam overlay
description: Reproduce and verify the working Steam overlay path inside a Moonshine HDR session.
when: Debugging or changing Moonshine, Gamescope WSI, HDR streaming, or the Steam overlay.
resource: modules/aspects/streaming.nix
tags: [moonshine, moonlight, gamescope, steam, overlay, hdr, gaming]
---

# Moonshine HDR Gamescope Steam overlay

Baseline confirmed working in Persona 3 Reload on `alpha` on 2026-09-08
(Moonshine 0.15.0, Gamescope 3.16.28). Preserve this path when changing the
streaming stack — in particular, do not re-enable Moonshine's WSI layer
around the nested Gamescope compositor.

The deciding factor is resolution, not window mode: the overlay works when
the game resolution is smaller than the Gamescope/Moonlight output
resolution, and fails when the two match. The current theory is that the 1:1
presentation path bypasses composition the overlay hook needs, but that
mechanism is unproven — the matrix below is the ground truth:

| Gamescope output | P3R resolution | P3R mode | Steam overlay |
| --- | --- | --- | --- |
| 3840x2160 | 1920x1080 | Fullscreen | Works |
| 3840x2160 | 3840x2160 | Fullscreen | Fails |
| 3840x2160 | 3840x2160 | Borderless | Fails |
| 1920x1080 | 1920x1080 | Fullscreen | Fails |
| 1920x1080 | 1920x1080 | Borderless | Fails |

## Known-good settings

P3R `GameUserSettings.ini` for the working case:

```ini
ResolutionSizeX=1920
ResolutionSizeY=1080
FullscreenMode=0
PreferredFullscreenMode=0
FrameRateLimit=60.000000
```

The working Gamescope invocation (4K output, HDR):

```text
gamescope --steam -f -b -W 3840 -H 2160 -w 3840 -h 2160 -r 60 \
  --hdr-enabled -- bwrap --dev-bind / / \
  --tmpfs /mnt/seagate --tmpfs /home/containers/media/seagate -- \
  steam -tenfoot
```

`bwrap` stays inside Gamescope: Gamescope creates Xwayland outside the user
namespace while the Seagate mounts stay hidden from Steam.

Required environment (see the HDR launcher in `streaming.nix`): the game
process must observe `ENABLE_GAMESCOPE_WSI=1`,
`GAMESCOPE_WSI_FIX_OVERLAY=1`, and
`ENABLE_VK_LAYER_VALVE_steam_overlay_1=1`, with Moonshine's own WSI layer
disabled. The local Gamescope patch (ValveSoftware/gamescope#1537) gives the
overlay an X11-backed swapchain at startup, then returns to the normal WSI
path after five seconds — that is what keeps HDR while letting the overlay
hook attach. Do not add `PROTON_ENABLE_WAYLAND=1`: it belongs to the failed
native Wine-Wayland experiment.

## Verify after a change

After rebuilding but before switching, confirm all of the following:

1. The generated Moonshine config contains the `Steam Big Picture HDR`
   application and no separate SDR Steam entry.
2. The Gamescope derivation enables its WSI layer and lists
   `gamescope-wsi-overlay.patch` in `patches`.
3. The HDR launcher sets `DISABLE_MOONSHINE_WSI=1` and
   `GAMESCOPE_WSI_FIX_OVERLAY=1`, does not set `PROTON_ENABLE_WAYLAND`, and
   launches Gamescope with `--hdr-enabled`.
4. In a live game, `/proc/$game_pid/environ` contains
   `ENABLE_GAMESCOPE_WSI=1`, `GAMESCOPE_WSI_FIX_OVERLAY=1`, and
   `ENABLE_VK_LAYER_VALVE_steam_overlay_1=1`.
5. For the known-good P3R test, keep the Moonlight/Gamescope output at 4K and
   set the game itself to 1920x1080 Fullscreen. Equal game and output
   resolutions are known to fail with the current patch.
6. Shift+Tab visibly opens and closes the Steam overlay in an SDR game launched
   through the HDR entry.
