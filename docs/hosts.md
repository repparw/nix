---
type: Host Profiles
title: Host Profiles
description: The alpha desktop, beta laptop, and pi server profiles.
resource: modules/hosts/
tags: [hosts, alpha, beta, pi]
---

# Host Profiles

The hosts share the baseline in `modules/defaults.nix` and add hardware or
workload-specific aspects in `modules/hosts/`.

## Alpha

`alpha` is the desktop workstation. It carries the heavier local service set,
gaming, streaming, and backup behavior.

Source: `modules/hosts/alpha.nix`

## Beta

`beta` is the laptop profile. It adds laptop-specific input, power, and display
handling to the shared baseline.

Source: `modules/hosts/beta.nix`

## Pi

`pi` is the Raspberry Pi 5 home server (aarch64, `192.168.0.4`). It runs the
home-automation LAN DNS server on systemd-resolved, ssh/mosh access, and
headless services in declarative nspawn containers (no desktop/GUI stack):

- `containers.homeassistant` (`10.231.136.2`) behind a local nginx vhost for
  `home.repparw.com`.
- `containers.hermes` (`10.231.136.3`) runs the Hermes Agent messaging gateway
  via upstream's NixOS module; state lives under `/home/repparw/services/hermes`
  so the alpha-side `buprpi` rsync job captures it. Gateway-only: outbound chat
  platforms, no inbound ports, no ingress vhost.

It boots `linuxPackages_latest` through the Raspberry Pi firmware and
generic-extlinux-compatible loader, with the user home on the NVMe volume and
activation via the repo flake. The SD card runs the official NixOS aarch64
sd-image layout; see the [deployment runbook](runbooks/deploy-pi-nixos.md).

Source: `modules/hosts/pi.nix`

## Related

- [Service model](services/service-model.md)
- [Restore service backups](runbooks/restore-service-backups.md)
- [Den aspect composition](architecture/den-aspect-composition.md)
