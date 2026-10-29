---
type: Architecture Concept
title: Ingress Policy
description: How one ingress-policy seam generates Traefik and Authelia configuration.
when: Read when changing service routing, proxy authentication, or ingress exceptions.
resource: modules/_services/ingress-policy.nix
tags: [architecture, services, proxy, authentication]
---

# Ingress Policy

`modules/_services/ingress-policy.nix` owns public routing and authorization
decisions. Its interface accepts the domain, validated service definitions,
and internal service URL resolver. It produces two adapter projections:

- Traefik routers, backends, and middleware configuration.
- Ordered Authelia access-control rules.

Ordinary service routes derive from each definition's `hostname`, `port`, and
`auth` mode. `bypass` uses no forward-auth middleware; `one_factor` and
`two_factor` use Authelia and produce matching access rules. `external`
requires an explicit policy implementation and otherwise fails evaluation.

Exceptional routes remain inside the policy implementation: the qBittorrent
UI/API split and the apex Glance route. Everything else, including Home
Assistant (hostname `home`, `bypass` auth), is an ordinary route derived from
metadata emitted by its owning service aspect; there is no service-specific
routing code. Identity providers, secrets, and application configuration
remain in their owning service modules.

## Adapters

`modules/_services/proxy.nix` owns Traefik's static configuration and installs
the Traefik projection. `modules/_services/authelia.nix` owns identity and
session configuration and installs the Authelia projection.

`modules/aspects/edge-tunnel.nix` connects Cloudflare Tunnel to Traefik's
loopback HTTPS listener on Epsilon. Its hostname allowlist comes from the
service registry, excluding Jellyfin, plus `grafana` and the temporary legacy
`metrics` hostname, both redirected by Traefik to the Grafana Cloud stack. TLS verification and
the existing Authelia rules apply along this path. Jellyfin keeps its
DNS-only home address; qBittorrent's UI/API uses the tunnel while its peer
traffic keeps its existing ports. Epsilon accepts direct HTTPS only from
the trusted home uplink and its private Glance container for local probes.
The apex DNS record points to the tunnel, so Epsilon no longer runs the
apex ddclient updater.
