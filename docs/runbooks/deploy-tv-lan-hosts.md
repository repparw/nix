---
type: Runbook
title: Deploy LAN hosts to LG C3
description: Export the fleet's generated LAN host mappings for the rooted webOS TV.
when: Read when updating the C3's local Jellyfin routing.
resource: modules/tv-lan-hosts.nix
tags: [tv, jellyfin, lan, dns]
---

# Deploy LAN hosts to LG C3

The service registry in `modules/aspects/services/default.nix` generates the
`modules.lan-hosts.file` fragment. The exported `tv-lan-hosts` package is
that same file, rather than a separately maintained list of IP addresses.

From the `repparw/nix` checkout:

```sh
hosts_file=$(nix build .#tv-lan-hosts --no-link --print-out-paths)
cat "$hosts_file"
```

The fragment sends `jellyfin.repparw.com` directly to the Pi LAN edge
(`192.168.0.4` at the time of writing). This bypasses the router's
working NAT loopback path; a high-bitrate 4K test over loopback buffered,
but that single test did not prove the router was the bottleneck.

To install, use the `repparw/homelab-devices` checkout:

```sh
cd /path/to/homelab-devices/tv
./deploy.sh --lan-hosts "$hosts_file"
```

That repository owns the persistent webOS boot hook, its on-device
fragment, and the idempotent application to `/etc/hosts`. It must
preserve the independently managed LG telemetry block. Avoid manually
editing the TV's hosts file as the permanent deployment mechanism.

The fragment is an **external TV deployment artifact**: building or
deploying the Nix fleet alone does not modify the C3. Test the output
before applying, and validate again after a TV reboot.
