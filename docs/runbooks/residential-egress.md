---
type: Runbook
title: Residential egress via the home tunnel
description: Opt workloads into home-IP egress through the wg-home SOCKS relay on Epsilon.
when: A site flags or rate-limits the VPS IP range, or you need to verify the relay path.
resource: modules/aspects/wg-egress-relay.nix
tags: [networking, wireguard, socks, epsilon, hermes]
---

# Residential egress via the home tunnel

Epsilon's default egress carries its VPS IP, which some sites flag. The
`wg-egress-relay` aspect provides an opt-in path: a SOCKS5 relay on Epsilon
whose outbound traffic is policy-routed through the `wg-home` tunnel, so
destinations see the home residential IP.

## Activation

The relay is **disabled by default**. Merely including the aspect on Epsilon
does not alter WireGuard routes, create a proxy listener, or add a firewall rule.
After separately verifying home-side NAT and authorizing the rollout, set
`modules.wg-egress-relay.enable = true;` on Epsilon and deploy the validated
configuration. Keep it disabled while this PR remains parked.

## How it works

- `microsocks` listens on the Epsilon bridge gateway (`10.231.137.1:1080`) as
  the dedicated `wg-egress-relay` user.
- A UID policy rule routes everything that user sends into routing table
  `51820`, whose default goes out `wg-home`.
- The table also holds a `blackhole default` with a worse metric: if the
  tunnel is down, relayed traffic fails instead of falling back to the VPS IP.
- A specific route returns client replies through `ve-hermes`. The rules and
  relay stop with the Hermes container, before its interface disappears.
- The main routing table is untouched — management, monitoring, the edge
  tunnel, and backups keep using eth0.
- The firewall only admits `ve-hermes` to the relay port. Widen by adding an
  `iifname` rule in `modules/aspects/wg-egress-relay.nix`; never expose the
  port further.

Automatic routes from `allowedIPs` are disabled. The existing three private
routes are installed explicitly; `0.0.0.0/0` is permitted by WireGuard but
installed only in the relay's policy table. The relay permits IPv4 sockets
only, so an IPv6 destination cannot bypass the policy.

## Prerequisite (home side, not managed here)

The WireGuard server at home must forward and masquerade the wg subnet
(at least `10.5.5.3`) out the home WAN. Until this is in place the relay is
inert: connections through it time out, and nothing else is affected.

## Use it

From a container that has access (today only `ve-hermes`):

```sh
curl -x socks5h://10.231.137.1:1080 https://ifconfig.me   # expect 45.237.179.43
```

Without container access, verify the path from the host directly:

```sh
curl -x socks5h://10.231.137.1:1080 https://ifconfig.me     # expect 45.237.179.43
curl https://ifconfig.me                                  # expect the VPS IP
```

Wiring a consumer to the relay (for example the Hermes browser's proxy
setting) is a separate change; this aspect only provides the path.
Hostname resolution still uses Epsilon's resolver; this is residential
destination egress, not a guarantee that DNS queries travel through home.

## Troubleshoot

```sh
ip rule show                                              # relay UID range present?
ip route show table 51820                                  # default + blackhole?
systemctl status wg-egress-relay wg-egress-rules
networkctl status wg-home
journalctl -u wg-egress-relay -n 50
```
