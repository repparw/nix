---
type: Runbook
title: Prepare pi and epsilon for persistent state
description: Staged persistence declarations, filesystem audit findings, and prerequisites for disposable host roots.
when: Read before enabling host persistence, changing the persistence inventory, or preparing an impermanence migration.
resource: modules/aspects/persistence.nix
tags: [impermanence, persistence, pi, epsilon, recovery, backups]
---

# Prepare pi and epsilon for persistent state

The `persistence` aspect imports nix-community/impermanence and records the
initial persistence inventory. Pi and epsilon include it. Alpha does not.
`modules.persistence.enable` defaults to `false`: including the aspect does
not create persistence mounts, move files, reset root, or change boot storage.

Enabling requires a separately prepared `/persist` filesystem marked
`neededForBoot`. Before activation, an initrd guard checks the backing machine ID, SSH key,
UID/GID state directory, account database when requested, and a
`.host-persistence-ready` marker containing the host name. This rejects an
empty or unprepared volume; it does not prove every application was copied
correctly. **Do not enable it on the existing layouts.** Live migration remains
pending: the available recovery access is SSH only.

When enabled, pi's existing home filesystem becomes required in the initrd
and loses `nofail`, so a missing NVMe cannot silently become an empty HA/user
data directory. Its normal, disabled configuration keeps the current options.

## Initial inventory

The initial set is conservative. Container roots and whole homes remain
persistent until their contents have been classified and independently tested.

| Scope                                     | Persistent state                                                                                                                                                          |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Shared                                    | `/etc/ssh`, `/etc/machine-id`, `/var/lib/nixos`, `/root`, `/var/lib/nixos-containers`, fail2ban state, Traefik certificates, systemd timer/timesync state and random seed |
| Pi                                        | `/home/containers/config`, `/var/lib/auto-update`, `/var/lib/fleet-health`, Bluetooth and radio block state                                                               |
| Pi, existing filesystem                   | The whole `/home/repparw` volume, including HA, user credentials, projects, AI tools and swap; it must be available before activation when persistence is enabled         |
| Epsilon                                   | `/home/repparw`, `/home/containers/config`, ddclient state and `/var/log`                                                                                                 |
| Storage design, separate from this module | Full `/nix`, full `/boot`, the firmware/EFI partitions, and `/persist` itself                                                                                             |

Pi's deployment controller had a `PAUSE` flag during the audit. Losing it would
change deployment behavior. Preserve it with the controller's remaining state.
Hosts with recovery backups enabled also retain `/var/lib/host-recovery`.
Epsilon retains `/var/lib/credential-remediation`: its existing Authelia and
Traefik service drop-ins run credential refresh helpers from that directory.
Preserving `/etc` without those helpers prevents both services from starting.
Epsilon's GRUB copies kernels and initrds to `/boot/kernels`. Both runtime
store aliases become bind mounts after a tmpfs-root boot; GRUB's mount-based
store path calculation would otherwise generate paths missing `/nix/store`.
GRUB accesses `/boot` through the backing path `/persist/boot` for the same
reason. See [Nixpkgs issue #309912](https://github.com/NixOS/nixpkgs/issues/309912).
`/var/lib/nixos` must be mounted before user allocation to keep the UID/GID map
consistent with the owners of persistent files.

When enabled, SOPS reads the SSH identity directly from
`/persist/etc/ssh/ssh_host_ed25519_key`. User-password secrets may be required
before `/etc/ssh` is mounted. Preserve the identity before booting the new
layout; generating a replacement key cannot decrypt the old secrets.

## Mutable passwords

`users.mutableUsers = true` remains in effect. The SOPS hash is a creation-time
bootstrap; subsequent `passwd` changes must survive activation and root reset.
With mutable users, enabling persistence requires the explicit choice
`modules.persistence.mutableAccounts = true`. This persists **all of `/etc`**,
including account databases, machine ID and SSH identity, and mounts it before
user activation. Both persistence options default to false.

This is a conservative first-migration tradeoff: undeclared files in `/etc`
also survive. Individual account-file bind mounts or symlinks are unsuitable
because PAM and NixOS replace those files atomically; see
[Impermanence issue #120](https://github.com/nix-community/impermanence/issues/120).
Keeping the directory lets ordinary password changes work without custom PAM
hooks. It does not require that passwords have ever been changed locally.
`/var/lib/nixos` separately retains UID/GID allocation state.

Before migration, preserve `/etc` with its numeric owners, modes and symlinks.
Test password equality without printing hashes. Changing the SOPS bootstrap
later is a separate operation and does not reset the existing password.

The mounted application state already covers HA's registries, pairings,
history and custom integrations; Authelia's authentication database; Miniflux's
PostgreSQL cluster and dumps; Paperless's documents/database; ASF's login
state; and Hermes's conversations, credentials, scheduled work and workspace.
The retained container roots also cover Authelia and Paperless Redis state.
Treat disposable container roots as a separate service-by-service migration.

Keep the configured owners and modes, numeric container UID/GID mappings,
ACLs, extended attributes and symlinks when copying state. Existing directory
ownership is not repaired automatically by Impermanence. In particular,
Hermes and Paperless use explicit shifted container users. Quiesce databases
or use their native backup/export tools for a consistent migration copy.

## Filesystem audit: 2026-09-26

A root-level metadata walk covered every mounted local disk filesystem:

| Host    | Filesystems walked                                           | Unique entries |
| ------- | ------------------------------------------------------------ | -------------: |
| Pi      | SD root, NVMe `/nix`, NVMe `/home/repparw`, `/boot/firmware` |        238,728 |
| Epsilon | ext4 root, `/boot/efi`                                       |        170,572 |

The walks recorded types, owners, modes, sizes, timestamps, paths and symlink
targets. Both completed without traversal errors. `/nix/store` was excluded
because it is immutable/reconstructible; `/nix/var` was included. Virtual and
temporary filesystems (`/proc`, `/sys`, `/dev`, `/run`, tmpfs `/tmp`) were not
treated as persistent data. Symlinks were recorded rather than followed.
Service working/state directories and local systemd/cron files were inspected
separately. No independent local cron or systemd unit files were found beyond
the known pi journald drop-in.

This is an inventory of a running system, not an atomic snapshot, a review of
every file's contents, or proof that every application can recover. The raw
metadata is private evidence and is not committed because it includes user
paths. No files were removed or services restarted during inspection.

Additional findings beyond the first targeted service audit:

- Epsilon retains `/old-root`, an Ubuntu migration tree (about 2.5 GiB of
  apparent regular-file data). Its unmounted ext4 `BOOT` partition, `/dev/sda16`,
  was inspected read-only with `debugfs`; it contains legacy boot assets.
  Retain these as recovery archives until separately reviewed.
- Pi has root-owned `HANDOFF-*.md` notes and `/root/nixos-config`. Keeping
  `/root` initially preserves these operator records as well as SSH trust.
- Pi retains an old host PostgreSQL cluster, NetworkManager state, old
  service/container trees, Podman storage, an HA trial copy, and TV/migration
  backups. These are archive/review candidates, not automatically disposable.
- Both homes contain GitHub/Google credentials, AI-tool databases, projects
  and worktrees. Pi additionally has local binaries and device tooling.
  Keep whole homes for the first root migration.
- `/srv` and the inspected mount-point directories contained no additional
  regular-file application data. Generated `/bin`, `/usr`, `/lib`, most of
  `/etc`, caches and logs do not imply separate application persistence needs.

User lingering is already declared in Nix. Epsilon's old dhcpcd lease and DUID
files are inactive: the current configuration uses networkd and disables
dhcpcd. Pi's radio block state is retained alongside its Bluetooth pairings.

The retained old root filesystem in a future tmpfs-root trial can keep archive
paths accessible beneath `/persist` without exposing them at their old paths.
Do not add deletion or repartitioning to that trial.

## Storage and recovery prerequisites

1. Complete a [full pi backup and isolated restore](host-recovery.md). Daily
   backup scope now includes identity, account files, whole homes, container
   roots and controller state on pi/epsilon. Daily jobs exclude reproducible
   caches and swap; the explicit full backup also includes `/nix/store` and
   caches, excluding runtime/temporary files and swap. Scope changes take
   effect only after normal deployment.
2. Verify recovery credentials outside the fleet. The personal recovery Age
   recipient derives from alpha's user SSH key. SSH key copies are reported
   in Bitwarden; test the matching retrieved private key as described in the
   [recovery runbook](host-recovery.md). A restore using epsilon's credentials
   proves recovery from losing pi, not from losing the whole fleet.
3. Use the VM check below for the shared mount/password/recovery behavior.
   Production service boot, ARM firmware and real disk attachment still need
   their own trial. The HA component migration and interactive Authelia/HA
   checks were completed with the declarative cleanup in PR #102.
4. Preserve the actual boot layout. Pi's extlinux configuration and kernels
   live under `/boot` on the SD root, outside `/boot/firmware`. Epsilon has
   `/boot/grub` outside `/boot/efi`. Both need more than their firmware partition.
5. Prepare the new root layout and an independently usable rescue boot. A
   tmpfs root can reuse ext4 as backing storage; no Btrfs conversion is needed.
   Epsilon also needs its existing `/nix` attached to the new root. Pi's home
   volume must fail closed rather than allow empty HA state on a missing disk.
   Write the readiness marker only after copying and verifying the backing
   data, and retain a bootable known-good disk or rescue console. **SSH alone
   cannot recover a failed initrd. Do not perform the live root migration.**
6. Once rescue access and restoration are proven, trial pi, then epsilon.
   Keep the root-layout change outside automatic fleet deployment. An ordinary
   generation rollback cannot reverse a repartition or restore missing data.

Paperless's registry export path now matches its actual `paper/export` mount.
Raw live database copies still require database-consistent restoration;
pi's full checkpoint includes a separate HA archive made with HA stopped.

## Alpha later

The shared identity policy, service-state inventory and container tests apply
to alpha. Its host aspect does not include persistence in this stage.

The live mount audit found `/home`, `/nix` and service data inside root subvolume
`@`; an `@home` subvolume exists but is not mounted at `/home`. Root rollback
would therefore encompass important data. Prowlarr also keeps its live database
and configuration in its container root; only its backup directory is bound
out. Resolve those boundaries and inventory desktop state before considering
alpha's root or home disposal.

## Implementation choice and verification

As of the audit, Impermanence had 1,893 GitHub stars and 36 contributors, with
the latest default-branch commit dated 2026-01-27. Preservation had 360 stars,
3 contributors and a latest commit dated 2025-09-09. These are adoption/activity
signals, not a guarantee of correctness. Both have relevant open ordering
issues. The flake locks Impermanence as a source-only input, without importing
its development dependencies.

Preservation uses systemd mounts and tmpfiles and requires a systemd initrd;
the pinned Nixpkgs already defaults to one. It is a viable smaller alternative,
but Impermanence has the larger contributor base and more recent activity.
Hand-written bind mounts would avoid a dependency while leaving path creation,
ownership and ordering to this repository.

Root reset is a separate choice from either persistence module. A tmpfs root
fits the ext4 layouts on pi and epsilon without repartitioning. An overlay over
the existing root retains undeclared dependencies; Btrfs rollback becomes an
option for alpha only after its data is separated from the root subvolume.

- [Impermanence](https://github.com/nix-community/impermanence)
- [Preservation](https://github.com/nix-community/preservation)
- [Impermanence SOPS ordering report](https://github.com/nix-community/impermanence/issues/294)
- [Preservation permission/ordering report](https://github.com/nix-community/preservation/issues/24)

`checks.<system>.host-persistence` evaluates disabled defaults, explicit
mutable-account consent, early UID/GID and SOPS ordering, backup coverage,
pi's separate home mount, epsilon's home persistence and alpha's exclusion.

`checks.x86_64-linux.host-persistence-vm` boots the actual persistence module
with a tmpfs root and ext4 backing disk. It uses disposable credentials and
checks:

- a real `passwd` change across activation, reboot and abrupt restart;
- stable SSH key, machine ID, SOPS decryption and UID allocation;
- application data, timer stamps and deployment pause state;
- the recovery helper's stopped-writer archive, encrypted backup and isolated
  restore, including identity, SOPS, SQLite, ownership, modes, ACLs and xattrs;
- failed boot with missing storage or an unprepared backing volume, followed
  by repair of the VM disk offline and a successful boot.

CI runs that VM separately from the evaluation gate. This is a synthetic x86
recovery test, not a boot of pi/epsilon's real service images or production data.

See the [configuration verification skill](../../.agents/skills/verify-nixos-config/SKILL.md)
and [fleet operations runbook](fleet-operations.md) for the separate build,
activation and runtime verification procedures.
