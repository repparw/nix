---
type: Service Architecture
title: Service Model
description: How service definitions, containers, proxying, monitoring, and backups fit together.
when: Read when adding services or changing shared service routing, monitoring, or backups.
resource: modules/aspects/services/default.nix
tags: [services, containers, proxy, backup]
---

# Service Model

Service behavior is split between the common host substrate, service bundles,
and individual service aspects.

- `service-host` collects the fleet service registry into the validated schema
  and provides the address allocator without selecting any services.
- `media-stack` composes Alpha's media services and shared container substrate.
- Hosts include only the individual `nixos-services._.*` aspects they run.
- `modules/aspects/services/default.nix` defines the substrate and bundles.
- `modules/aspects/services/` contains service-owned implementation and metadata.
- `modules/_services/` contains shared service infrastructure and adapters.
- `modules/service-definitions.nix` defines the validated service-definition shape.
- `modules/_services/proxy.nix` owns proxy routing.
- `modules/_services/ingress-policy.nix` generates Traefik and Authelia policy
  from service definitions.
- `modules/_services/glance.nix` owns dashboard and monitoring presentation.

Each service aspect emits its reachability, routing, monitoring, and backup
facts through the `service-registry` quirk. A fleet-wide `collectAll` pipe
collects those facts with provenance, so `service-host` derives each service's
`host` from the originating host entity. The host entity's `serviceAddress`
field supplies cross-host reachability and is folded into
`modules.services.hostAddresses`; there is no separate address registry.
`service-host` then folds the registry into `modules.services.definitions`,
preserving the validated compatibility seam used by existing consumers.
Invalid routed or monitored definitions and duplicate names or container
hostnames fail evaluation there.

Definition fields drive host behavior as follows:

- `hostname` and `domain` produce the public host name and proxy router.
- `host` and `container` determine host membership and whether the allocator
  assigns a private bridge address.
- `port` produces the proxy backend URL.
- `auth` selects the proxy authentication middleware where routing is generic.
- `monitor` adds the public URL and internal check URL to Glance.
- `backup.path` produces the read-only backup export and container ordering.

Service-specific settings, mounts, devices, secrets, and exceptional proxy
rules remain local to the owning service aspect.

Private containers use the gateway derived from the host's
`modules.services.bridgePrefix` (`10.231.136.1` by default; epsilon uses
`10.231.137.1`). Service backup exports are gathered under
`modules.services.backupDir`, which defaults to `/home/containers/backup`.

## Related

- [Ingress policy](../architecture/ingress-policy.md)
- [Restore service backups](../runbooks/restore-service-backups.md)
- [Check native container DNS](../runbooks/check-native-container-dns.md)
- [Host profiles](../hosts.md)
