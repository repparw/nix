---
type: Host Profiles
title: Host Profiles
description: The alpha desktop and pi server profiles, plus the parked beta laptop.
when: Read when comparing host profiles or adding or changing a host.
resource: modules/hosts/
tags: [hosts, alpha, beta, pi]
---

# Host Profiles

The hosts share the baseline in `modules/defaults.nix` and add hardware or
workload-specific aspects in `modules/hosts/`.

## Alpha

`alpha` is the desktop workstation. It carries the heavier backend service
set (media, *arr stack, documents), gaming, streaming, and backup behavior.
Since the edge migration it is no longer the public entrypoint: pi fronts
every `*.repparw.com` vhost and reaches alpha's published backends over the
LAN.

Source: `modules/hosts/alpha.nix`

## Beta

`beta` is the laptop profile. It adds laptop-specific input, power, and display
handling to the shared baseline. It is parked: its host attachment is commented
out in `modules/aspects/repparw.nix`, so it does not participate in flake
evaluations until it has hardware again.

Source: `modules/hosts/beta.nix`

## Pi

`pi` is the Raspberry Pi 5 home server (aarch64, `192.168.0.4`) and the
always-on public edge: Traefik terminates `*.repparw.com` with Authelia SSO
in front, ddclient owns dynamic DNS, and LAN DNS runs on systemd-resolved.
Headless services run in declarative nspawn containers (no desktop/GUI
stack):

- Traefik (:80/:443) routes every vhost; local backends target the nspawn
  bridge, remote ones alpha's published ports (`_services/inventory.nix`).
- `containers.authelia` (`10.231.136.7`) provides SSO/forward-auth/OIDC.
- `containers.homeassistant` (`10.231.136.2`) serves `home.repparw.com`.
- `containers.hermes` (`10.231.136.3`) runs the Hermes Agent messaging gateway
  via upstream's NixOS module; state lives under `/home/repparw/services/hermes`
  so the alpha-side `buprpi` rsync job captures it. Gateway-only: outbound chat
  platforms, no inbound ports, no ingress vhost.

It boots through the Raspberry Pi firmware and generic-extlinux-compatible
loader (linuxPackages_latest, with the `pcie_brcmstb` module in the initrd
so stage-1 enumerates the NVMe), with home, store, and swap on the NVMe
volume and activation via the repo flake. The SD card runs the official
NixOS aarch64 sd-image layout; see the
[deployment runbook](runbooks/deploy-pi-nixos.md).

Source: `modules/hosts/pi.nix`

## Related

- [Service model](services/service-model.md)
- [Restore service backups](runbooks/restore-service-backups.md)
- [Den aspect composition](architecture/den-aspect-composition.md)
