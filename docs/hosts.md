---
type: Host Profiles
title: Host Profiles
description: The alpha desktop, pi home server, and epsilon VPS edge profiles.
when: Read when comparing host profiles or adding or changing a host.
resource: modules/hosts/
tags: [hosts, alpha, pi, epsilon]
---

# Host Profiles

The hosts share the baseline in `modules/defaults.nix` and add hardware or
workload-specific aspects in `modules/hosts/`.

## Alpha

`alpha` is the desktop workstation (x86_64, `192.168.0.18`). It carries the
heavier backend service set (media, *arr stack), gaming,
streaming, and backup behavior. Since the edge migrations it is not a
public entrypoint: epsilon terminates the public vhosts, and pi fronts
alpha's published service backends over the LAN.

The fleet prepares all hosts concurrently, then activates epsilon, alpha, and
pi in that order. Pi is last because it runs the deployment controller.
All preparation must succeed before the first activation, and each host must
pass its health checks before the next one starts.
See the
[fleet operations runbook](runbooks/fleet-operations.md).

Source: `modules/hosts/alpha.nix`

## Pi

`pi` is the Raspberry Pi 5 home server (aarch64, `192.168.0.4`) and the
always-on host: it runs the LAN HTTPS edge for Jellyfin, the Home Assistant
container, fleet-health, and the deploy-rs controller. Home Assistant's
public HTTPS route uses Epsilon's Cloudflare Tunnel. Authelia, Miniflux, and
Glance live on epsilon.

It is the fleet's deployment controller. GitHub Actions opens lock update PRs,
validates their exact lock commit, and atomically fast-forwards main to that
same SHA when main has not moved. Pi then reuses that exact successful CI result
while staging the revision through epsilon, alpha, and finally pi with
deploy-rs.

- Traefik (:443) fronts `jellyfin.repparw.com` only — the fleet's one direct
  WAN HTTPS entrypoint, reached through the router's TCP 443 port-forward.
  The DNS-only `jellyfin` A record is stable because the home WAN IP is
  static, so no DDNS updater is needed for it. Jellyfin's backend is alpha's
  published port.
- `containers.homeassistant` serves `home.repparw.com` through the Cloudflare
  tunnel via epsilon, not through pi's Traefik.
- Fleet-health monitoring and the `fleet-controller` auto-update pipeline run here.
- `free-games-claimer.service` claims Epic/GOG free games on Pi's residential
  connection. Its daily timer and temporary virtual display are described in
  the [free-games-claimer guide](services/free-games-claimer.md).

It boots through the Raspberry Pi firmware and generic-extlinux-compatible
loader (linuxPackages_latest, with the `pcie_brcmstb` module in the initrd
so stage-1 enumerates the NVMe), with a tmpfs root backed by `/persist` on
the SD card and home, store, and swap on the NVMe volume. A mirror SD backup
is the primary recovery path; see the [host recovery runbook](runbooks/host-recovery.md).

Source: `modules/hosts/pi.nix`

## Epsilon

`epsilon` is the Oracle Cloud Always Free A1 VPS (aarch64,
sa-santiago-1) and the terminating public edge: Cloudflare fronts it, its
firewall accepts 443 from CF ranges only, and Traefik terminates the
public vhosts with Authelia SSO. Installed in place via nixos-infect
(grub removable EFI on the Ubuntu partition layout).

- `containers.authelia`, `containers.miniflux`, `containers.glance`, and
  `containers.hermes` use point-to-point nspawn veths allocated from
  `10.231.137.0/24`. A host-specific early networkd rule leaves those links
  under NixOS container ownership; the firewall explicitly owns forwarding
  and masquerades the allocation range only toward `eth0` and `wg-home`.
  Containers resolve through the host at `10.231.137.1`; Glance's monitors
  probe public endpoints through the home tunnel where required.
- `containers.hermes` runs the Hermes Agent messaging gateway here
  (migrated from pi).
- `containers.archisteamfarm` runs the Steam bot here (migrated from pi
  for VPS uptime; not LAN-dependent, not exposed).
- `containers.paperless` holds the document archive here (migrated from
  alpha). Traefik reaches it on the local bridge; it is not published
  on the VPS public address.
- A split-tunnel WireGuard link (`wg-home`, via the router's hub) reaches
  the home LAN and pi's container bridge for monitoring and agent egress.
- Offsite restic covers its stateful edge services under
  `gd-crypt:restic/epsilon`.

It is the first stage of the fleet's deploy-rs update, before alpha and then pi.

Source: `modules/hosts/epsilon.nix`

## Persistence and backups

Pi and epsilon use tmpfs roots with durable state under `/persist`. Their
mutable-account policy persists `/etc`; host state and service exports also
have offsite backups. Local persistence alone does not provide offsite recovery.
See the [host persistence runbook](runbooks/host-persistence.md) and
[host recovery runbook](runbooks/host-recovery.md).

## Related

- [Service model](services/service-model.md)
- [Restore service backups](runbooks/restore-service-backups.md)
- [Den aspect composition](architecture/den-aspect-composition.md)
