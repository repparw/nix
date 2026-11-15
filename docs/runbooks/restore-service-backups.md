---
type: Runbook
title: Restore service backups
description: Restore service data from exported backup paths.
when: Read when restoring service data from an exported backup.
resource: modules/aspects/backup.nix
tags: [runbook, recovery, services, backups]
---

# Restore service backups

Service backup exports are gathered under `modules.services.backupDir`, which
defaults to `/home/containers/backup`. Most service backup paths are read-only
bind mounts from `/home/containers/config`.

Stop, restore, and restart operations change live state. Obtain explicit
authorization for the selected service before proceeding.

1. Find the backup source and stop the affected service:

   ```sh
   service=sonarr # replace with the affected native container
   ls -lah /home/containers/backup
   sudo systemctl stop "container@${service}.service"
   ```

   For native host services, use the service unit directly, for example
   `sudo systemctl stop miniflux.service`.

2. Restore into the live config path under `/home/containers/config/<service>`.
   Keep the owners, modes, and existing path layout. For database dumps, such as
   Miniflux's, restore through the database tooling. Do not copy the dump over
   the live data directory.

3. Start the service and inspect the logs:

   ```sh
   sudo systemctl start "container@${service}.service"
   journalctl -u "container@${service}.service" -b
   ```

## Related

- [Offsite host recovery](host-recovery.md)
