---
type: Runbook
title: Moonshine HDR Gamescope Steam overlay
description: Reproduce and verify the working Steam overlay path inside a Moonshine HDR session.
when: Debugging or changing Moonshine, Gamescope WSI, HDR streaming, or the Steam overlay.
resource: modules/aspects/streaming.nix
tags: [moonshine, moonlight, gamescope, steam, overlay, hdr, gaming]
---

# Moonshine HDR Gamescope Steam overlay

The Steam overlay was confirmed visible in Persona 3 Reload on `alpha` on
2026-09-08. Preserve this path when changing the streaming stack; in
particular, do not re-enable Moonshine's WSI layer around the nested Gamescope
compositor.

Across every tested variation, the overlay works when the game resolution is
smaller than the Gamescope/Moonlight output resolution and fails when the two
resolutions match. Window mode is not the deciding factor: at a 1080p
Gamescope output, the overlay failed in P3R in both Fullscreen and Borderless
modes.

## Confirmed working baseline

The observed live system was
`/nix/store/gqp8l6pqz473fzh15k6pcq8mxlsaj3rd-nixos-system-alpha-26.11.20260907.dc5d91f`.
It ran:

- Moonshine 0.15.0 from
  `/nix/store/lsbc83vzyyxf1wcmhcavi4h8q1hcqz13-moonshine-0.15.0`;
- Gamescope 3.16.28 from
  `/nix/store/w2z3y4iyzr9y2x2lbh1s9zd6j0q2p0jp-gamescope-3.16.28`;
- the `Steam Big Picture HDR` Moonshine application at 3840x2160 and 60 Hz;
- Persona 3 Reload at 1920x1080 Fullscreen under GE-Proton through
  Steam/pressure-vessel.

The observations form this test matrix:

| Gamescope output | P3R resolution | P3R mode | Steam overlay |
| --- | --- | --- | --- |
| 3840x2160 | 1920x1080 | Fullscreen | Works |
| 3840x2160 | 3840x2160 | Fullscreen | Fails |
| 3840x2160 | 3840x2160 | Borderless | Fails |
| 1920x1080 | 1920x1080 | Fullscreen | Fails |
| 1920x1080 | 1920x1080 | Borderless | Fails |

The tested invariant therefore points to Gamescope's scaled/composited path as
the enabling condition. It is plausible that the 1:1 presentation path
bypasses composition behavior needed by the overlay proof of concept, but that
mechanism has not been proven.

The known-working P3R `GameUserSettings.ini` values were:

```ini
ResolutionSizeX=1920
ResolutionSizeY=1080
FullscreenMode=0
PreferredFullscreenMode=0
FrameRateLimit=60.000000
```

For comparison, the controlled 1080p Borderless test used
`FullscreenMode=1` and `PreferredFullscreenMode=1` and failed, as did the
subsequent 1080p Fullscreen retest at a 1080p Gamescope output.

The Gamescope derivation had `enable_gamescope_wsi_layer=true` and applied
[`gamescope-wsi-overlay.patch`](../../modules/aspects/gamescope-wsi-overlay.patch).
The applied store copy and repository copy both had SHA-256
`cd95208d6c198e708bd60159496a334bbba2430ab02f550947fa5f730cd8524d`.

The effective Gamescope command was:

```text
gamescope --steam -f -b -W 3840 -H 2160 -w 3840 -h 2160 -r 60 \
  --hdr-enabled -- bwrap --dev-bind / / \
  --tmpfs /mnt/seagate --tmpfs /home/containers/media/seagate -- \
  steam -tenfoot
```

`bwrap` must remain inside Gamescope. This lets Gamescope create Xwayland
outside the user namespace while still hiding the Seagate mounts from Steam.

## Required WSI behavior

The HDR launcher in
[`streaming.nix`](../../modules/aspects/streaming.nix) establishes these key
variables:

```text
DISABLE_MOONSHINE_WSI=1
GAMESCOPE_WSI_FIX_OVERLAY=1
```

It also removes `ENABLE_MOONSHINE_WSI`, leaves Gamescope WSI enabled, and puts
both Moonshine and Gamescope in `XDG_DATA_DIRS`. The game process was observed
with `ENABLE_GAMESCOPE_WSI=1` and
`ENABLE_VK_LAYER_VALVE_steam_overlay_1=1`.

The local patch implements the proof of concept discussed in
ValveSoftware/gamescope#1537. With `GAMESCOPE_WSI_FIX_OVERLAY=1`, it gives the
Steam overlay an X11-backed swapchain during startup, then returns subsequent
presentation to the normal Gamescope WSI path after five seconds. This keeps
the HDR path while allowing Steam's overlay hook to attach.

Do not add `PROTON_ENABLE_WAYLAND=1` to this baseline. That was part of the
unsuccessful native Wine-Wayland experiment and is not present in the working
process environment.

## Client observations

The Android Moonlight client connected using H.265 10-bit at 3840x2160. It
requested SDR Rec.709 even though it launched the HDR application; Moonshine
logged the colorspace mismatch and converted the Gamescope surface. The Steam
overlay still rendered.

Moonlight's performance overlay showed a clean network path (3 ms RTT and zero
network frame drops). The approximately 30 FPS result in Persona 3 Reload was
instead accompanied by the game saturating the RX 6700 XT. Moonshine's color
conversion used about 1% GFX in the same sample, so do not attribute that
performance result to the overlay patch.

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
