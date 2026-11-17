---
type: Tweaks
title: Tweaks
description: Named micro-adjustments and the source file or option each one touches.
when: Read when applying a small named adjustment, or when tracing which option controls one.
resource: modules/hosts/alpha.nix
tags: [tweaks, alpha, storage, edge, probes]
---

# Tweaks

Small, named adjustments. Each entry names the source file or option it touches.
Procedures stay where they live, and this page links to them instead of
duplicating them.

## GE-Proton automatic FSR upgrade

The gaming aspect sets `PROTON_FSR4_UPGRADE=1` in the launcher environments of
Steam and Heroic, including Heroic shortcuts inside Steam. GE-Proton picks its
default DLL from the upstream upscaler manifest. The managed runner stays
`GE-Proton`.

Compatible games that use their FSR 3.1 integration can use the automatic
upgrade. The flag does not select an in-game upscaler, convert arbitrary FSR2
integrations, or guarantee that the selected model supports the GPU. FSR 4.1 on
Alpha's RX 6700 XT still needs runtime verification, tracked in
[issue #323](https://github.com/repparw/nix/issues/323).

To disable the upgrade for one Steam game, set its launch options to
`PROTON_FSR4_UPGRADE=0 %command%`. For a Heroic game, add `PROTON_FSR4_UPGRADE`
with the value `0` to that game's environment settings. To diagnose, temporarily
set `PROTON_FSR4_INDICATOR=1` for the game, and remove the setting after you
check the active upscaler. After you activate a changed launcher package,
restart the launcher.

Touches: `modules/aspects/gaming.nix` (`gamingEnvironment`, Steam's `extraEnv`,
and the Heroic package override).

## Spin down alpha's media HDD

The WD80EAZZ ignores the ATA standby timer. `hdparm -S` and
`smartctl --set standby` are clamped to a vendor minimum, and that minimum never
engages, so scheduled standby never fires. The only way to spin the drive down
is STANDBY IMMEDIATE (`hdparm -y`), guarded by `findmnt` on the disk label.
`findmnt` reads mountinfo and does not touch the automount. A statvfs check
through `mountpoint` would reset the idle timer and defeat the sweep.

Touches: `modules/hosts/alpha.nix` (`systemd.services.hdd-spindown`,
`systemd.timers.hdd-spindown`, every 5 minutes).

## Probe HTTPS edges with SNI intact

Both Traefik edges set `tls.options.default.sniStrict = true`, so probing by IP
without a hostname fails even when the backend is healthy. Pi's LAN Traefik
routes Jellyfin only. Home Assistant uses the public Cloudflare Tunnel to
Epsilon, so do not force its hostname to Pi's loopback.

Probe the public Home Assistant route using normal DNS:

```sh
curl -fsS -o /dev/null -w '%{http_code}\n' https://home.repparw.com/
```

To exercise Pi's _local_ Jellyfin edge while keeping SNI:

```sh
curl -fsS --resolve jellyfin.repparw.com:443:127.0.0.1 \
  -o /dev/null -w '%{http_code}\n' https://jellyfin.repparw.com/health
```

Only LAN-edge vhosts have static `/etc/hosts` entries on fleet hosts. Public
HTTPS names use regular DNS, and SSH still uses direct machine addresses.

Touches: `modules/aspects/services/default.nix`,
`modules/aspects/services/fleet-health.nix`, `modules/_services/proxy.nix`,
and `modules/aspects/lan-edge.nix`.
