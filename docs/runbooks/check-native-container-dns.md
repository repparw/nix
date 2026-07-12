---
type: Runbook
title: Check Native Container DNS
description: Diagnose DNS resolution for private NixOS containers.
resource: modules/aspects/services/default.nix
tags: [runbook, dns, containers, services]
---

# Check Native Container DNS

Private containers use `networking.useHostResolvConf = false` and resolve
through the host bridge at `10.231.136.1`. The host exposes `systemd-resolved`
with `DNSStubListenerExtra = "0.0.0.0"`.

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

3. If lookup fails, verify the container still points at `10.231.136.1`, the
   host firewall accepts `ve-*` DNS traffic, and
   `services.resolved.settings.Resolve.DNSStubListenerExtra` is still enabled.

## Related

- [Service model](../services/service-model.md)
