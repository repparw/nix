---
type: Host Profiles
title: Host Profiles
description: The alpha desktop, pi home server, and epsilon VPS edge profiles, plus the parked beta laptop.
when: Read when comparing host profiles or adding or changing a host.
resource: modules/hosts/
tags: [hosts, alpha, beta, pi, epsilon]
---

# Host Profiles

The hosts share the baseline in `modules/defaults.nix` and add hardware or
workload-specific aspects in `modules/hosts/`.

## Alpha

`alpha` is the desktop workstation (x86_64, `192.168.0.18`). It carries the
heavier backend service set (media, *arr stack, documents), gaming,
streaming, and backup behavior. Since the edge migrations it is not a
public entrypoint: epsilon terminates the public vhosts, and pi fronts
alpha's published service backends over the LAN.

Alpha is the final stage of deploy-rs fleet updates and is activated only when
every local graphical user session is idle, locked, or no longer active. This
policy also defers for block-mode systemd sleep inhibitors, so a remote game or
media stream remains active even when the physical session is locked. It
ignores delay-mode and non-sleep inhibitors. The policy comes from alpha's
desktop aspect rather than its host name. Pi schedules the retry against the
current main revision when the fleet pass deferred or could not reach alpha,
ensuring every deployment shares one controller mutex and alpha never updates
the system from inside a unit being replaced.
See the
[fleet operations runbook](runbooks/fleet-operations.md).

Source: `modules/hosts/alpha.nix`

## Beta

`beta` is the laptop profile. It adds laptop-specific input, power, and display
handling to the shared baseline. It is parked: its host attachment is commented
out in `modules/aspects/repparw.nix`, so it does not participate in flake
evaluations until it has hardware again.

Source: `modules/hosts/beta.nix`

## Pi

`pi` is the Raspberry Pi 5 home server (aarch64, `192.168.0.4`) and the
always-on host: it runs the LAN-side edge (Traefik with Authelia SSO) and
the declarative nspawn services that must survive workstation downtime.
It is also the fleet's **sole flake.lock writer and deployment controller**:
one nightly transaction publishes a validated candidate to main, and an
independent later transaction stages exact current main through epsilon, pi,
and idle alpha with deploy-rs.

- Traefik (:80/:443) routes the LAN vhosts; local backends target the
  nspawn bridge, remote ones alpha's published ports
  (the service aspects' `service-registry` emissions).
- `containers.authelia` (`10.231.136.7`) provides SSO/forward-auth/OIDC.
- `containers.homeassistant` (`10.231.136.2`) serves `home.repparw.com`.
- `containers.miniflux` (`10.231.136.4`) serves `rss.repparw.com`.
- Fleet-health monitoring and the `fleet-controller` auto-update pipeline run here.

It boots through the Raspberry Pi firmware and generic-extlinux-compatible
loader (linuxPackages_latest, with the `pcie_brcmstb` module in the initrd
so stage-1 enumerates the NVMe), with home, store, and swap on the NVMe
volume and activation via the repo flake. The SD card runs the official
NixOS aarch64 sd-image layout; see the
[deployment runbook](runbooks/deploy-pi-nixos.md).

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
- A split-tunnel WireGuard link (`wg-home`, via the router's hub) reaches
  the home LAN and pi's container bridge for monitoring and agent egress.
- Offsite restic covers its stateful edge services under
  `gd-crypt:restic/epsilon`.

It is the first stage of the fleet's deploy-rs update, limiting blast radius
before the home controller and desktop are activated.

Source: `modules/hosts/epsilon.nix`

## Related

- [Service model](services/service-model.md)
- [Restore service backups](runbooks/restore-service-backups.md)
- [Den aspect composition](architecture/den-aspect-composition.md)
