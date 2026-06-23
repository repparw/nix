---
type: Service Architecture
title: Service Model
description: How service modules, containers, proxying, inventory, and backups fit together.
resource: modules/aspects/services/default.nix
tags: [services, containers, proxy, backup]
---

# Service Model

Service behavior is split between the service aspect and individual service
modules.

- `modules/aspects/services/default.nix` composes the service aspect.
- `modules/_services/` contains NixOS service modules imported by the service
  aspect.
- `modules/service-inventory.nix` defines the service inventory option shape.
- `modules/_services/proxy.nix` owns proxy routing.
- `modules/_services/glance.nix` owns dashboard and monitoring presentation.

Private containers use the host bridge at `10.231.136.1`. Service backup
exports are gathered under `modules.services.backupDir`, which defaults to
`/home/containers/backup`.

## Related

- [Restore service backups](../runbooks/restore-service-backups.md)
- [Check native container DNS](../runbooks/check-native-container-dns.md)
- [Alpha](../hosts/alpha.md)
