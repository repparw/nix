---
type: Runbook
title: Restore host state from offsite backups
description: Inspect and restore pi or epsilon state with native Restic, independently of persistence.
when: Read before testing an offsite host restore or changing pi or epsilon boot storage.
resource: modules/aspects/backup.nix
tags: [runbook, recovery, backups, pi, epsilon, impermanence]
---

# Restore host state from offsite backups

Use native Restic to inspect and restore the daily offsite snapshots. The
manual `host-recovery` command has been retired. Existing snapshots and local
`/var/lib/host-recovery` artifacts remain intact and covered by daily backups.

## Inspect scope and consistency

Before a storage change, inspect the evaluated job and the live mount layout:

```sh
nix eval .#nixosConfigurations.pi.config.services.restic.backups.offsite.paths --json
nix eval .#nixosConfigurations.pi.config.services.restic.backups.offsite.exclude --json
findmnt
```

Pi and Epsilon compose [host-backup](../../modules/aspects/host-backup.nix).
It supplies identity and account
files under `/etc`, `/root`, the whole user home, container roots, NixOS UID
allocation, timer stamps, legacy recovery artifacts, and Traefik state.
Host-specific additions cover bound application state and controller state.
Alpha keeps its separate, narrower policy with prepared application backups.
Alpha's home-state staging also carries the fleet's OpenTofu state; see
[Restore the OpenTofu state](#restore-the-opentofu-state).

Daily jobs use `--one-file-system`. Restic compares device IDs: it traverses
same-device bind mounts but skips nested filesystems on other devices unless
they are explicit backup roots. Each configured path is its own root, so the
bind-mounted `/etc`, homes, and container state are included. Nested firmware
and EFI partitions are included explicitly alongside `/boot`. Compare the
configured paths with `findmnt` whenever the layout changes.

Persistence and offsite coverage are separate policies. `/persist` itself is
not a backup root: undeclared archives beneath it, `/nix/store`, and persistent
paths outside the configured job remain outside daily scope. Restic does not
follow symlinks to add their targets. Daily jobs exclude reproducible caches,
container runtime mounts, and swap. Do not interpret a successful daily job as
a full-disk image or an atomic application snapshot.

Use native application backups or exports for consistent database restoration.
The [scheduled offsite operation](fleet-operations.md) refreshes its registered
native producers before upload. Start `restic-backups-offsite.service` to run
that same path manually.
Other live pi and epsilon filesystem copies do not stop databases. Old
`application-state.tar` checkpoints, when present, describe their capture time;
this change does not refresh them. See [Restore service backups](restore-service-backups.md).
Before repartitioning or discarding state beyond daily scope, make and verify
an independent checkpoint of that state and preserve the boot layout.

## Restore the OpenTofu state

The fleet's OCI cloud resources are managed by OpenTofu from `infra/` in this
repository. The authoritative local state lives on alpha at
`~repparw/Projects/nix/infra/terraform.tfstate` (mode 0600); the compartment
OCID it needs at plan time sits next to it in `terraform.tfvars`. The state is
a live pointer to Oracle Cloud resources — treat it as more valuable than the
repository: re-cloning Git recovers the configuration, while losing the state
loses drift history and the imported-resource identities.

Coverage:

- **Off-site (encrypted):** alpha stages the state into
  `/var/lib/home-state-backup/offsite/Projects/nix/infra/terraform.tfstate`
  and the daily `restic-backups-offsite` job uploads the whole staging tree to
  `rclone:gd-crypt:restic/alpha`.
- **Local HDD:** the same staging tree is mirrored by `rsync-job-bupstate` to
  `/mnt/hdd/backup/Projects/nix/infra/terraform.tfstate`.
- `terraform.tfstate.backup` (OpenTofu's automatic pre-change copy) is
  deliberately not staged: restic snapshots already provide generation
  history.
- State, tfvars, and provider caches are gitignored — never commit or
  SOPS-encrypt state files into the repository. Even with no credentials in
  the currently managed resources, state files can contain sensitive data
  (resource metadata, addresses, secrets passed via tooling) and grow into it
  silently.

Recovery into an isolated directory (never over the live path), as root on
alpha:

```sh
export RESTIC_REPOSITORY=rclone:gd-crypt:restic/alpha
export RESTIC_PASSWORD_FILE=/run/secrets/resticPassword
export RCLONE_CONFIG=/run/secrets/rendered/rclone.conf
restic snapshots --tag home-state-verify  # or list all and pick by date
RESTORE_DIR=$(umask 077; mktemp -d /var/tmp/tfstate-restore.XXXXXX)
restic restore --verify "$SNAPSHOT_ID" --target "$RESTORE_DIR" \
  --include /var/lib/home-state-backup/offsite/Projects/nix/infra/terraform.tfstate
restored="$RESTORE_DIR/var/lib/home-state-backup/offsite/Projects/nix/infra/terraform.tfstate"
tofu state list -state="$restored"   # expect the eight managed resources
sha256sum "$restored" ~/Projects/nix/infra/terraform.tfstate
```

HDD copies restore the same way without the repository environment:
`/mnt/hdd/backup/Projects/nix/infra/terraform.tfstate`. Validate with
`tofu state list -state=...` before using any recovered copy, and compare
checksums against the live file when both exist.

Prefer a restored snapshot over re-importing: the snapshot preserves the
exact serial and resource identities the fleet last applied. Re-running the
import mappings in `infra/imports.tf` is the fallback when no snapshot is
available — it re-derives state from the live cloud, but silently adopts any
out-of-band drift as the new baseline.

After any `tofu apply`, import, state migration, or manual state repair on
alpha, capture a fresh backup in both destinations immediately:

```sh
sudo systemctl start --wait home-state-backup-offsite.service
sudo systemctl start --wait rsync-job-bupstate.service
sudo systemctl start --wait restic-backups-offsite.service
```

Run this manually rather than from a hook: a failed backup must never fail or
retry an otherwise successful infrastructure change. The staging script
refuses to publish a generation while OpenTofu holds the state lock, and
after the first successful backup it refuses to publish a generation at all
if the state file has disappeared — the failed unit is retained by fleet
health until repaired, so a deleted state cannot silently drop out of
coverage.

## Restore into an isolated directory

Run as root on a host with the existing rendered backup credentials. Set
`SNAPSHOT_ID` to a completed snapshot's hexadecimal ID from `restic snapshots`.
For example, inspect pi's repository from epsilon:

```sh
export RESTIC_REPOSITORY=rclone:gd-crypt:restic/pi
export RESTIC_PASSWORD_FILE=/run/secrets/resticPassword
export RCLONE_CONFIG=/run/secrets/rendered/rclone.conf
restic snapshots
restic ls "$SNAPSHOT_ID"
umask 077
RESTORE_DIR=$(mktemp -d /var/tmp/host-restore.XXXXXX)
restic restore --verify "$SNAPSHOT_ID" --target "$RESTORE_DIR"
```

Confirm the rendered credential paths against the host's evaluated job before
use. If Restic or rclone is absent from the rescue environment, provide both
with `nix shell nixpkgs#restic nixpkgs#rclone`. Never print the password or
rendered rclone configuration. Logs and restored trees contain private data.
Require a successful restore exit and keep the isolated tree for inspection.

Check restored account files, SSH identity, application exports, and numeric
ownership before considering a real restore. When restoring old checkpoints,
verify the identity manifest from the restored root and the application manifest
from its artifact directory, without printing the recorded hashes:

```sh
(cd "$RESTORE_DIR"; sha256sum --check --quiet var/lib/host-recovery/identity.sha256)
(cd "$RESTORE_DIR/var/lib/host-recovery"; sha256sum --check --quiet application-state.sha256)
```

Run each check only when its manifest exists. Extract a stopped-application archive into
a separate directory with numeric ownership, ACLs, and xattrs preserved.
Check SQLite integrity and use the application's native restore validation.
These checks do not prove external-device connectivity or interactive login.

Before a real restore, use rescue access, reconcile disks and firmware, restore
state with its numeric ownership and attributes, and verify the boot path.
A successful offsite rehearsal does not make a failed initrd recoverable over
SSH. Never restore over live paths during a rehearsal or apply partition tables
to a running host. Recreate swap rather than restoring its contents.

## Recovery after losing the whole fleet

The personal Age recipient in `.sops.yaml` matches the Age conversion of
alpha's user SSH public key, `~/.ssh/id_ed25519.pub`. Its corresponding private
SSH key can recreate the Age identity; a separate Age key file is unnecessary.
The owner reports three SSH keys stored in Bitwarden. Confirm the matching
entry by testing a copy retrieved from the vault; possession of the key on
alpha alone does not verify the off-fleet backup.

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

- [Change host persistence](host-persistence.md)
- [Fleet operations](fleet-operations.md)
- [Restore service backups](restore-service-backups.md)
- [Secret inventory](../architecture/secret-inventory.md)
