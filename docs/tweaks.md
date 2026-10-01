---
type: Tweaks
title: Tweaks
description: Named micro-adjustments and the source file or option each one touches.
when: Read when applying a small named adjustment, or when tracing which option controls one.
resource: modules/hosts/alpha.nix
tags: [tweaks, alpha, storage, edge, probes]
---

# Tweaks

Small, named adjustments. Each entry states the source file or option it
touches; procedures stay where they live and this page links instead of
duplicating them.

## Spin down alpha's media HDD

The WD80EAZZ ignores the ATA standby timer (`hdparm -S` and
`smartctl --set standby` are clamped by a vendor minimum that never engages),
so scheduled standby never fires. The only lever is STANDBY IMMEDIATE
(`hdparm -y`), guarded by `findmnt` on the disk label: `findmnt` reads
mountinfo and must not touch the automount, while a statvfs check via
`mountpoint` would reset the idle timer and defeat the sweep.

Touches: `modules/hosts/alpha.nix` (`systemd.services.hdd-spindown`,
`systemd.timers.hdd-spindown`, every 5 minutes).

## Probe traefik with SNI intact

Both edges set `tls.options.default.sniStrict = true`, so only clients that
present a known SNI hostname get a route — probing by IP, or with a client
that sends no SNI, is rejected even when the backend is healthy. Probe the
FQDN and pin it to localhost so SNI stays correct:

```sh
curl --resolve home.repparw.com:443:127.0.0.1 https://home.repparw.com/
```

Touches: `modules/_services/proxy.nix`, `modules/aspects/lan-edge.nix`;
the working pattern is the fleet-health vhost probes in
`modules/aspects/services/fleet-health.nix`.
