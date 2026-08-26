---
type: Runbook
title: Check Native Container DNS
description: Diagnose DNS resolution for private NixOS containers.
when: Read when diagnosing DNS failures in native NixOS containers.
resource: modules/aspects/services/default.nix
tags: [runbook, dns, containers, services]
---

# Check Native Container DNS

Private containers use `networking.useHostResolvConf = false` and resolve
through the host's `systemd-resolved`. Expected values differ per host:

- `alpha` exposes resolved on all addresses
  (`DNSStubListenerExtra = "0.0.0.0"`); containers target the host bridge at
  `10.231.136.1`.
- `pi` hosts the running containers and exposes resolved on
  `192.168.0.4:53` and `10.231.136.1:53`, forwarding to Cloudflare (Quad9
  fallback) over DoT. Its containers target `192.168.0.4`.

1. Check host-side DNS first:

   ```sh
   resolvectl status
   ss -lunpt | rg ':53'
   systemctl status systemd-resolved.service
   ```

2. Check the container resolver and a known lookup:

   ```sh
   sudo nixos-container run <service> -- cat /etc/resolv.conf
   sudo nixos-container run <service> -- getent hosts cache.nixos.org
   sudo nixos-container run <service> -- resolvectl query cache.nixos.org
   ```

3. If lookup fails, verify the container still points at its host's expected
   resolver (`10.231.136.1` on alpha, `192.168.0.4` on pi), the host firewall
   accepts `ve-*` DNS traffic, and
   `services.resolved.settings.Resolve.DNSStubListenerExtra` still carries the
   host's expected listeners.

## Related

- [Service model](../services/service-model.md)
