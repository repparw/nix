---
type: Service Architecture
title: Service Model
description: How service definitions, containers, proxying, monitoring, and backups fit together.
resource: modules/aspects/services/default.nix
tags: [services, containers, proxy, backup]
---

# Service Model

Service behavior is split between the service aspect and individual service
modules.

- `modules/aspects/services/default.nix` composes the service aspect.
- `modules/_services/` contains NixOS service modules imported by the service
  aspect.
- `modules/service-definitions.nix` defines the validated service-definition shape.
- `modules/_services/proxy.nix` owns proxy routing.
- `modules/_services/ingress-policy.nix` generates Traefik and Authelia policy
  from service definitions.
- `modules/_services/glance.nix` owns dashboard and monitoring presentation.

Shared reachability, routing, monitoring, and backup facts belong in
`modules.services.definitions`. Consumers derive their configuration from that
definition. Invalid routed or monitored definitions and duplicate container
addresses fail evaluation at this seam.

Definition fields drive host behavior as follows:

- `hostname` and `domain` produce the public host name and proxy router.
- `containerAddress` selects the private-container endpoint; services without
  one use the host loopback endpoint.
- `port` produces the proxy backend URL.
- `auth` selects the proxy authentication middleware where routing is generic.
- `monitor` adds the public URL and internal check URL to Glance.
- `backup.path` produces the read-only backup export and container ordering.

Service-specific settings, mounts, devices, secrets, and exceptional proxy
rules remain local to the owning service module.

Private containers use the host bridge at `10.231.136.1`. Service backup
exports are gathered under `modules.services.backupDir`, which defaults to
`/home/containers/backup`.

## Related

- [Ingress policy](../architecture/ingress-policy.md)
- [Restore service backups](../runbooks/restore-service-backups.md)
- [Check native container DNS](../runbooks/check-native-container-dns.md)
- [Alpha](../hosts/alpha.md)
