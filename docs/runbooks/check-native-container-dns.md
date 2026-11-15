---
type: Runbook
title: Diagnose native container DNS
description: Distinguish host resolver, container gateway, and firewall failures.
when: Read when a native NixOS container cannot resolve domain names.
resource: modules/aspects/services/default.nix
tags: [runbook, dns, containers, services]
---

# Diagnose native container DNS

Containers intentionally use the host's bridge resolver instead of an
independent upstream DNS configuration. This keeps name resolution and
network-policy decisions under the host's control. The service aspects and the
host's effective NixOS configuration declare the resolver listeners, gateway
addresses, and firewall permissions. Do not copy the per-host address table into
a runbook.

Check host resolution and the listener first:

```sh
resolvectl status
ss -lunpt | rg ':53'
systemctl status systemd-resolved.service
```

Then check the affected container:

```sh
container=sonarr # replace with the affected native container
sudo nixos-container run "$container" -- cat /etc/resolv.conf
sudo nixos-container run "$container" -- getent hosts cache.nixos.org
sudo nixos-container run "$container" -- resolvectl query cache.nixos.org
```

If the host resolves but the container does not, compare the container's
nameserver with its host bridge address. Then inspect the firewall rules on
`ve-*` interfaces and the active resolved listener. A failed lookup alone does
not tell you whether the problem is routing, firewall policy, the resolver, or
the upstream DNS provider.
