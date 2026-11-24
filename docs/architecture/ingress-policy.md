---
type: Architecture Concept
title: Ingress policy decisions
description: Reasons for centralized routing and authorization.
when: Read when reviewing authentication bypasses, public exposure, or ingress design.
resource: modules/_services/ingress-policy.nix
tags: [architecture, services, proxy, authentication]
---

# Ingress policy decisions

Routing and authorization must come from the same validated service
definitions. Otherwise a Traefik route could bypass a separate Authelia policy,
or a newly exposed service could silently inherit the wrong access rule.
[The ingress policy](../../modules/_services/ingress-policy.nix) generates both
the routes and the authorization rules from one source. It rejects unsupported
external authentication modes instead of guessing a fallback. Its default
authorization policy is deny.

Authentication exceptions and health-check bypasses are security decisions.
Before you broaden one, review its intended consumers and its explicit route and
path restrictions. Keep any such exception in the shared policy, and do not add
one-off proxy routes in a service module.

Public ingress normally uses Cloudflare Tunnel, with separate direct paths only
where their purpose requires them. Local access, DNS, certificate handling, and
the actual allowlists live in the Nix modules. Do not maintain a second list of
public endpoints or firewall ports in this document.
