---
type: Runbook
title: Back up and restore a complete host
description: Full filesystem checkpoints and isolated restore verification before changing pi or epsilon boot storage.
when: Read before a root migration, taking a complete pi backup, or testing offsite host recovery.
resource: modules/aspects/backup.nix
tags: [runbook, recovery, backups, pi, epsilon, impermanence]
---

# Back up and restore a complete host

Live root migration is pending because recovery access is SSH only. Complete
the backup and restore rehearsal first; a successful rehearsal does not make
a failed initrd recoverable over SSH.

## Scope and consistency

The `host-recovery` command is available on pi and epsilon after deploying
`modules.backup.hostRecovery.enable`. It can also be built and copied as a
standalone package without activating a generation:

```sh
nix build .#nixosConfigurations.pi.config.modules.backup.hostRecovery.package --no-link --print-out-paths
```

`full` backs up each declared ext4, vfat, btrfs or xfs filesystem separately
with `--one-file-system`. Compare the generated `recovery-filesystems` list
against `findmnt` before using it on a changed layout: undeclared disks and
other filesystem types require explicit handling. On pi this covers `/`,
`/nix`, `/home/repparw` and `/boot/firmware`, including `/boot` on the root
filesystem, the complete Nix store, caches and old migration archives.
Pseudo-filesystems, runtime/temporary directories, Restic's cache, swap and
duplicate container runtime/Nix mounts are excluded. Daily backups have a
smaller scope and also exclude reproducible caches.

This is a full file backup, not a raw disk image or atomic whole-system
snapshot. The helper records partition tables, filesystem IDs, mount layout,
current/booted system paths and an identity/account checksum manifest under
root-only `/var/lib/host-recovery`. It also includes the encrypted host
password bootstrap file. It does not copy unmounted partitions or partition
boot sectors. Recreate pi's 8 GiB swap file rather than restoring swap contents.

On pi, `full --quiesce` stops Home Assistant, archives its complete state with
numeric ownership, modes, ACLs, xattrs and symlinks, compares that archive with
the stopped source, and restarts HA **before the offsite upload**. Failure
cleanup also attempts to restart previously running units. `capture` makes
only the local archive and metadata. HACS and mutable integrations remain
part of the archive. The ordinary live HA files may change during upload;
use the separate archive for database-consistent HA recovery.

Epsilon has no quiesced application paths configured yet. Its full backup
preserves live files, but database recovery still requires native exports or
a separate stopped-service checkpoint. Do not interpret its checkpoint tag
alone as proof that every database is consistent.

## Capture and inspect

Run as root with the generated package (or its absolute store path):

```sh
systemd-run --unit=host-recovery-full --property=Type=oneshot \
  --property=TimeoutStartSec=2d host-recovery full --quiesce
systemctl status host-recovery-full.service
journalctl -u host-recovery-full.service
```

The helper holds the fleet update lock to prevent deployment during capture
and upload. Allow substantial time for the first transfer. Confirm HA is
active after the local capture. Require successful unit completion and save
the exact snapshot ID from Restic's JSON summary; a progress report or uploaded
packs without a completed snapshot do not prove a usable backup. Treat logs
as private because Restic can include user file paths.

Use the existing rendered rclone configuration and Restic password file;
never print either. The package defaults to its host's repository. Environment
overrides `RESTIC_REPOSITORY`, `RESTIC_PASSWORD_FILE`, `RCLONE_CONFIG` and
`RESTIC_CACHE_DIR` support recovery using another machine's credentials.

## Rehearse restoration off-host

Use epsilon's existing backup credentials to restore a pi snapshot into a
fresh directory on epsilon, with enough free space for the entire tree and
the extracted HA checkpoint. No production path is replaced. For example,
with `SNAPSHOT_ID` set to the completed snapshot's hexadecimal ID:

```sh
RESTIC_REPOSITORY=rclone:gd-crypt:restic/pi \
  host-recovery restore-check "$SNAPSHOT_ID"
```

The command performs a full `restic restore --verify`, checks the restored
identity/account manifest without printing hashes, converts the restored SSH
key into a temporary Age identity, and decrypts the restored bootstrap
ciphertext to `/dev/null`. It removes that temporary identity on exit.

If present, the HA archive is checksum-verified and extracted separately from
the live file copy, preserving ownership and metadata. HA's database must
exist and pass SQLite `integrity_check`. A successful exit reports which
checks passed and retains the root-only `/var/tmp/host-recovery-restore.*`
tree for inspection. A failed check also leaves the tree for diagnosis.
Do not publish it, copy its private keys into the repository, or mistake a
successful database check for a test of external devices or OIDC login.

Before an eventual real restore, use rescue access, reconcile disk layout and
firmware requirements, restore state with numeric ownership and attributes,
and verify the old boot path works. Only then prepare the persistence mounts.
Do not run partition-table restoration commands against a running host.

## Recovery after losing the whole fleet

The personal Age recipient in `.sops.yaml` is public metadata. It proves
nothing about possession of its private identity. As of this preparation,
an off-fleet private-key copy has **not been confirmed**.

Locate that identity in a password manager or offline storage. Compare its
derived public recipient with `.sops.yaml`, and test decryption of the backup,
rclone and host bootstrap SOPS files on an independent machine, redirecting
plaintext away from logs. Also retain access to the Git repository and Google
account/recovery factors. Do not paste private keys or passwords into chat.

If the identity cannot be found, create a replacement on the independent
machine, store it there securely, add its public recipient to the appropriate
rules, and rekey while an existing host can still decrypt. Verify the new
identity before removing the old recipient. Merely creating another key on
pi/epsilon/alpha does not establish independent recovery.

## Related

- [Prepare pi and epsilon for persistent state](host-persistence.md)
- [Fleet operations](fleet-operations.md)
- [Restore service backups](restore-service-backups.md)
- [Secret inventory](../architecture/secret-inventory.md)
