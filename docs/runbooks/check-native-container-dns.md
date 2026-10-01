---
type: Runbook
title: Check Native Container DNS
description: Diagnose DNS resolution for private NixOS containers.
when: Read when diagnosing DNS failures in native NixOS containers.
resource: modules/aspects/services/default.nix
tags: [runbook, dns, containers, services]
---

# Check Native Container DNS

Private containers use `networking.useHostResolvConf = false`. Expected
resolvers differ per host:

- `alpha` exposes resolved on all addresses
  (`DNSStubListenerExtra = "0.0.0.0"`); containers target the host bridge at
  `10.231.136.1`.
- `epsilon` exposes resolved on its bridge gateway (`10.231.137.1`);
  containers resolve through the host, which forwards upstream.
- `pi` runs no resolver for containers: `containers.homeassistant` resolves
  upstream directly (`1.1.1.1`, `9.9.9.9`) out of the masqueraded bridge.

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

3. If lookup fails, verify the container points at its host's expected
   resolver (`10.231.136.1` on alpha, `10.231.137.1` on epsilon, or the
   container's own public nameservers on pi), the host firewall accepts
   `ve-*` DNS traffic, and
   `services.resolved.settings.Resolve.DNSStubListenerExtra` still carries the
   host's expected listeners.

## Related

- [Service model](../services/service-model.md)
