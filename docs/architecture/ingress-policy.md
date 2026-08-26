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
its definition in `_services/inventory.nix`; there is no code service.
Identity providers, secrets, and application configuration remain in their
owning service modules.

## Adapters

`modules/_services/proxy.nix` owns Traefik's static configuration and installs
the Traefik projection. `modules/_services/authelia.nix` owns identity and
session configuration and installs the Authelia projection.
