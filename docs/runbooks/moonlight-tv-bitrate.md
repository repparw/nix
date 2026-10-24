---
type: Runbook
title: Moonlight TV 200 Mbps Bitrate Build
description: Build, install, verify, and roll back the patched Moonlight TV IPK with a 200 Mbps bitrate slider on the rooted LG C3, plus the Wi-Fi capacity measurements that justify the ceiling.
when: Read when rebuilding or reinstalling the patched Moonlight TV app, when verifying the bitrate slider after a TV update, or when re-validating the Wi-Fi headroom for a new bitrate target.
resource: modules/_packages/moonlight-tv-bitrate
tags: [runbook, moonlight, webos, lg-c3, streaming, wifi, alpha]
---

# Moonlight TV 200 Mbps Bitrate Build

The rooted LG C3 (webOS 11.2, OLED55C3PSA) runs Moonlight TV
`com.limelight.webos` against Moonshine on Alpha. Upstream caps the bitrate
slider at the TV decoder's advertised `maxBitrate` (95–100 Mbps in practice).
This build raises the selectable maximum to 200 Mbps with a three-line patch,
preserving everything else (HDR, controller support, pairing, settings).

## The patch

`modules/_packages/moonlight-tv-bitrate/bitrate-200mbps.patch` contains the
entire functional delta against upstream tag `v1.6.37`:

1. `src/app/ui/settings/panes/basic.pane.c` — bitrate slider maximum fixed at
   200000 kbps instead of `video_cap.maxBitrate` (default 100000).
2. `src/app/stream/session.c` — the `maxBitrate` clamp is skipped on webOS
   (`#if !defined(TARGET_WEBOS)`), because the SS4S NDL driver advertises a
   conservative ceiling that does not reflect what the decoder sustains.
3. `cmake/AresPackage.cmake` — drop `--force-arch`, which newer ares-cli
   versions no longer accept (packaging-only, no runtime effect).

Nothing else is changed: no decoder, UI, networking, or buffer changes. HDR
and controller support are untouched code paths.

## Build (reproducible)

Source revision: upstream `mariotaku/moonlight-tv` tag **v1.6.37**
(commit `0b76df2bd4efb765d4e1cfdc1860d28e9c2463e3`), submodules at the gitlinks
recorded by that tag. The same tag as the previously installed build, so the
install is an in-place same-version upgrade with only the patch applied.

Toolchain: webOS NDK (buildroot) from
`openlgtv/buildroot-nc4@webos-b17b4cc`
(`arm-webos-linux-gnueabi_sdk-buildroot.tar.gz`). On NixOS the SDK's x86-64
host binaries need their ELF interpreters pointed at the Nix glibc (see
`patchsdk.sh` in the build scratch dir, or patch `bin/toolchain-wrapper` plus
`libexec/gcc/arm-webos-linux-gnueabi/12.2.0/*`); the SDK also needs
`LD_LIBRARY_PATH=<sdk>/lib` for `cc1` (libisl).

```sh
git clone --depth 1 --branch v1.6.37 https://github.com/mariotaku/moonlight-tv
cd moonlight-tv
git submodule update --init --recursive
git apply <repo>/modules/_packages/moonlight-tv-bitrate/bitrate-200mbps.patch

export WEBOS_NDK=/path/to/arm-webos-linux-gnueabi_sdk-buildroot
export TOOLCHAIN_FILE=$WEBOS_NDK/share/buildroot/toolchainfile.cmake
export CI=1                      # skip submodule auto-update
export LD_LIBRARY_PATH=$WEBOS_NDK/lib:$LD_LIBRARY_PATH
./scripts/webos/easy_build.sh    # cmake + cpack; produces dist/com.limelight.webos_1.6.37_arm.ipk
```

`easy_build.sh` invokes cpack, which shells out to `ares-package` (from
`@webos-tools/cli`, e.g. a `node_modules/.bin` on PATH) and `objdump` (nixpkgs
`binutils`). Verify the artifact before installing:

```sh
ares-package -i dist/com.limelight.webos_1.6.37_arm.ipk
# -> Package: com.limelight.webos / Version: 1.6.37 / Architecture: arm / main: bin/moonlight
```

## Install (pairing-preserving)

On webOS, Moonlight stores pairing keys, hosts, and settings **inside the app
directory** (`$HOME/conf`, where `$HOME` is the app folder): `conf/key/*.pem`,
`conf/hosts.ini`, `conf/moonlight.ini`. A same-ID reinstall recreates that
directory, so the conf must survive the install.

Use this procedure (2026-10-24: `ares-install -d tv` fails on this setup —
the ares-cli ssh2 transport uploads the IPK but its exec channel dies with
"Unable to exec"; `luna-send` calls only return output when run over a TTY,
i.e. `ssh -tt`). The manual path below is byte-identical to what the
installer does — this IPK ships no preinst/postinst scripts, only
`data.tar.gz` containing `usr/palm/applications/` + `usr/palm/packages/`.

1. Close Moonlight and confirm the process is gone (the install script must
   refuse to run otherwise):

   ```sh
   ssh -tt tv 'luna-send -n 1 -w 5000 -f luna://com.webos.applicationManager/closeByAppId \
     "{\"id\":\"com.limelight.webos\"}"; pgrep moonlight || echo closed'
   ```

2. Back up the app directory (repeat even if a backup exists — it is cheap):

   ```sh
   ssh tv 'cd /media/developer/apps/usr/palm/applications && tar czf - com.limelight.webos' \
     > moonlight-$(date +%Y%m%d-%H%M%S).tar.gz
   scp moonlight-*.tar.gz tv:/tmp/moonlight-backup.tar.gz   # on-TV copy for instant rollback
   ```

3. Extract the IPK payload on the build host and push it (busybox tar on the
   TV cannot read the `ar`-wrapped IPK):

   ```sh
   mkdir ipk-x && cd ipk-x && ar x ../dist/com.limelight.webos_1.6.37_arm.ipk
   scp -O data.tar.gz tv:/tmp/data.tar.gz
   ```

4. Install on the TV — keep conf aside, replace app + package registry,
   restore conf **before launching**:

   ```sh
   ssh -tt tv '
     set -e
     APP=/media/developer/apps/usr/palm/applications/com.limelight.webos
     PKG=/media/developer/apps/usr/palm/packages/com.limelight.webos
     pgrep moonlight >/dev/null && { echo REFUSING; exit 1; }
     mv "$APP/conf" /tmp/conf-keep
     rm -rf "$APP" "$PKG"
     tar xzf /tmp/data.tar.gz -C /media/developer/apps
     mv /tmp/conf-keep "$APP/conf"
     chmod -R 777 "$APP" "$PKG"
     chown -R root:jailer "$APP"; chown -R 5606:jailer "$APP/conf"
     ls "$APP/conf/key/"    # expect client.pem key.pem uniqueid.dat
     grep -c "^\[" "$APP/conf/hosts.ini"   # expect >= 1 (alpha)
   '
   ```

   If a previous attempt died between the `mv` and the `mv` back, `conf` is in
   `/tmp/conf-keep` — never `rm -rf` the app dir before confirming where conf
   is. The Alpha-side tarball is the authoritative fallback.

5. Launch and verify:

   ```sh
   ssh -tt tv 'luna-send -n 1 -w 5000 -f luna://com.webos.applicationManager/launch \
     "{\"id\":\"com.limelight.webos\"}"; sleep 5; pgrep moonlight'
   ```

   In Moonlight settings the bitrate slider must reach **200 Mbps**. Streaming
   to alpha must pair without a new pairing prompt. Version shown stays
   1.6.37 (the patch is behavioural, not a version bump — see rollback note).

## Rollback

Restore the pre-patch app directory from the on-TV copy (or the Alpha-side
tarball if the TV copy is gone):

```sh
ssh tv 'systemctl is-active moonshine || true   # ensure no stream is live
  cd /media/developer/apps/usr/palm/applications
  rm -rf com.limelight.webos
  tar xzf /tmp/moonlight-backup.tar.gz'          # archive root IS com.limelight.webos/
```

Then relaunch Moonlight and confirm the slider caps at 95–100 Mbps again and
pairing still works (conf is the original). If `/tmp` was cleared by a TV
reboot, pull the Alpha-side tarball back with `scp` first.

## Wi-Fi capacity measurements

Method: `iperf3 3.21` server on Alpha (192.168.0.18, wired eth0), client
`/tmp/iperf3 3.17.1` cross-compiled with the same webOS NDK on the TV
(wlan0). TCP 3×20 s per direction, UDP 2×15 s @300 M per direction for
jitter/loss. Run only with the Moonlight session stopped. iperf3 numbers are
an upper bound for streaming (Moonlight adds real-time pacing and per-frame
packets); treat ~70–80 % of measured TCP throughput as the realistic
streaming budget.

TV radio: MediaTek MT7668 USB module (`wlan_mt7668_usb` driver, USB
043e:310e), 2 spatial streams (VHT 2SS, 867 Mbps PHY ceiling), Wi-Fi 5
(802.11ac, `wifi_generation=5`), 5 GHz ch 149 (5745 MHz), signal ≈ −49 dBm,
WPA2-PSK/CCMP. Alpha is wired (eth0 192.168.0.18).

Results (2026-10-24, 16:50, link idle, full log in the PR thread / local
`wifi-bench-results.txt`; raw method: TCP 3×20 s per direction, UDP 2×15 s
@300 M per direction):

| Direction | TCP sustained | TCP retr (20 s) | UDP @300 M delivered | UDP jitter | UDP loss |
| --- | --- | --- | --- | --- | --- |
| Alpha→TV (streaming dir) | **262 Mbps** (250–290 flat) | **0** | 268 Mbps | 0.05–0.08 ms | 11 % (pushed past capacity) |
| TV→Alpha (upload) | **21 Mbps** | 172–184 | 21 Mbps | 0.74 ms | 91 % (same 300 M push) |

Link-state before/after: negotiated TX rate 585–780 Mbit/s, signal −49 dBm,
**0 tx failed** across ~990 k TX packets during the run. Baseline RTT
(Alpha→TV, 20 pings): min/avg/max 1.6/2.8/3.6 ms, 0 % loss.

Two findings worth knowing:

1. **The link is strongly asymmetric.** The streaming direction (Alpha→TV)
   sustains ~260 Mbps with zero TCP retransmissions; the TV's transmit path
   caps at ~21 Mbps with heavy retransmissions. Moonlight's return traffic
   (input events, control channel) is tiny, so this does not constrain
   streaming — but it rules out any workload that uploads heavily from the TV.
2. **UDP ≠ streaming capacity.** The 11 % UDP loss at 300 M is an artifact of
   pushing past link capacity with no congestion control; the TCP result with
   0 retransmissions is the meaningful ceiling for a paced, congestion-aware
   stream. Moonlight's own traffic is paced per-frame, closer to the TCP
   behaviour than the UDP blast.

## Interpretation

- 4K60 HDR needs roughly 80–100 Mbps sustained; 1440p60 HDR needs 40–60.
- **Recommended ceiling on this Wi-Fi link: 150 Mbps** (≈57 % headroom below
  the measured 262 Mbps streaming-direction floor). **200 Mbps is plausible
  but thin** (≈24 % headroom) — usable on quiet air, but expect it to show
  network drops if a neighbour network shares the channel or microwave
  interference appears. Choose 200 for wired-only setups.
- 95 → 150 Mbps is the practical sweet spot on Wi-Fi: visibly better texture
  retention in motion at well under half the measured capacity. The step from
  150 → 200 is smaller (diminishing HEVC returns) and eats the safety margin.
- The bottleneck ladder, from the measured data: at 1440p60 the host already
  processes ~58 FPS at 95 Mbps (Moonshine encoding + game rendering dominate);
  the network is not the limiter below ~200 Mbps. At 4K60 the host becomes the
  limiter first (~42 FPS at 95 Mbps) — raising the client bitrate will not fix
  host processing time, so do not expect bitrate to change host latency.
- If sustained TCP throughput in the Alpha→TV direction drops below ~120 Mbps,
  stay at 150 Mbps or below on Wi-Fi and treat 200 Mbps as a wired-only
  setting. A USB Ethernet adapter on the TV (rooted; `rtl8150` and
  `ax88179_178a` drivers are present in the kernel) bypasses the radio
  entirely and is the only path that makes 200 Mbps boring.
