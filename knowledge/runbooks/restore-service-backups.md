---
type: Runbook
title: Restore Service Backups
description: Restore service data from exported backup paths.
resource: modules/aspects/backup.nix
tags: [runbook, recovery, services, backups]
---

# Restore Service Backups

Service backup exports are gathered under `modules.services.backupDir`, which
defaults to `/home/containers/backup`. Most service backup paths are read-only
bind mounts from `/home/containers/config`.

1. Find the backup source and stop the affected service:

   ```sh
   ls -lah /home/containers/backup
   systemctl stop container@<service>.service
   ```

   For native host services, use the service unit directly, for example
   `systemctl stop miniflux.service`.

2. Restore into the live config path under `/home/containers/config/<service>`.
   Preserve owners, modes, and existing path layout. For database dumps such as
   Miniflux, restore through the database tooling instead of copying the dump
   over the live data directory.

3. Start the service and inspect logs:

   ```sh
   systemctl start container@<service>.service
   journalctl -u container@<service>.service -b
   ```

## Related

- [Service model](../services/service-model.md)
- [Alpha](../hosts/alpha.md)
