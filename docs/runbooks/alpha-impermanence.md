---
type: Runbook
title: Prepare alpha for a volatile root
description: Disabled persistence inventory, proposed backing layout, and prerequisites for alpha's first tmpfs-root boot.
when: Read before enabling alpha persistence, changing its storage layout, or reviewing its first volatile-root trial.
resource: modules/aspects/alpha-persistence.nix
tags: [alpha, impermanence, persistence, btrfs, recovery, desktop]
---

# Prepare alpha for a volatile root

Alpha includes a disabled persistence inventory. Its root remains Btrfs, no
`/persist` mount is declared, and no files move. Enabling
`modules.persistence.enable` alone fails assertions. The root-layout change
and first boot require a separate reviewed configuration and recovery trial.

## Current storage

The read-only mount audit on 2026-10-14 found `/home`, `/nix`, and service data
inside root subvolume `@` on UUID `51c5e80b-e22e-4d62-a3e2-ebb531deb05b`.
The existing `@home` subvolume is not mounted at `/home`; do not assume it
contains the current home. The ESP is independently mounted at `/boot`.

HDD and Seagate are outside the migration scope. Do not format, repartition,
move data, change ownership, alter mount declarations, or place migration
backups on either disk. Preserve their existing filesystem and bind-mount
declarations exactly.

Their media is mounted below `/home/containers/media`. Exclude `/mnt/hdd`,
`/mnt/seagate`, and the media bind-mount trees from migration scans, copies,
and recovery backups. Persisting `/home` must not copy the mounted media into
`/persist/home`; reuse the NVMe-backed home and preserve the existing nested
mounts. Preserve numeric owners, ACLs, extended attributes, and container UID
mappings for the NVMe state.

Prowlarr retains its live database in its container root. Its exported backup
directory is not the whole live database. Keep `/var/lib/nixos-containers`
until each container has an independent restart and restore test.

## Initial inventory

Keep the whole `/home` for the first migration. This preserves credentials,
Codex and T3 state, projects and worktrees, game saves, user services, container
configuration, and downloads. A volatile home is a separate project.

The shared aspect retains host identity, mutable-account allocation state,
container roots, root's home, and systemd timer state. The alpha aspect adds
desktop/network device state, private service state, operational records,
backup staging, and logs. The declared paths are in
[alpha-persistence.nix](../../modules/aspects/alpha-persistence.nix).
Service aspects also contribute their own persistence entries.

Set `modules.persistence.mutableAccounts = true` in the later boot candidate
to retain the complete `/etc`, including local `passwd` changes. It mounts
before user allocation; SOPS reads the prepared SSH identity directly from
`/persist/etc/ssh`. The random seed is regenerated per boot, matching the
same-filesystem transition policy on pi and epsilon.

The remaining `/var/lib` directories include legacy service and virtualization
trees. The old root must remain accessible under `/persist` while those paths
are classified. This inventory is a first draft, not a complete filesystem
audit or proof that omitted state is disposable.

## Proposed backing layout

Use a tmpfs root and mount the existing `@` subvolume at `/persist`, explicitly
selecting `subvol=@`. Bind `/persist/nix` into `/sysroot/nix` in the systemd
initrd before `initrd-nixos-activation.service`, following epsilon's existing
store-bind ordering. Keep the complete Nix store and database together.

Impermanence then exposes retained `/persist/home`, `/persist/etc`, and the
other declared paths at their original locations. Reusing the existing
subvolume avoids copying the whole home or store into alpha's limited free
space. It does not make the backing state disposable: never reset or delete
`@` after it becomes `/persist`.

The backing mount needs `neededForBoot = true`. Create the
`.host-persistence-ready` marker containing `alpha` only after the identity,
account databases, store, homes, and service state have been verified. The
shared initrd guard rejects an absent or unprepared backing volume.

No part of this draft mounts the backing filesystem or switches the root.

## Before the first boot

1. Finish the filesystem and enabled-service inventory. Check desktop login,
   networking, Bluetooth, printers, virtual machines, games, and media state.
2. Expand alpha's recovery coverage and prove an isolated restore. Its current
   offsite backup is a small home-state allowlist; it omits OAuth credentials,
   most of the home, complete container roots, and host identity. Persistence
   declarations are not backups. Scope this recovery work to NVMe state and
   exclude the HDD, Seagate, and their media bind mounts explicitly. Do not
   broaden or redirect backup jobs onto either disk as part of this migration.
3. Verify independently usable rescue media and local console access. Keep
   the current Btrfs-root boot entry and its store closure as a recovery path.
   SSH cannot recover an initrd that failed to mount the NVMe.
4. Stop service writers or export databases before taking recovery checkpoints.
   Retain the original backing data and independently verify ownership and
   credential readability without printing their contents.
5. Build and inspect the complete tmpfs-root candidate and its initrd. Test
   the `/persist` and `/nix` ordering, early account mounts, missing-volume
   refusal, and readiness-marker refusal in a disposable Btrfs VM first.
6. Perform a local-console first boot outside automatic fleet deployment.
   Verify service health, existing passwords, SOPS decryption, desktop login,
   T3/Codex credentials, and a second reboot. Prove the recovery boot entry
   before making the candidate the fleet default.

## Recovery preparation analysis, 2026-10-14

Decision: keep persistence disabled. No backup, restore, snapshot, balance,
activation, reboot, or disk-layout change was performed during this analysis.
The media disks were excluded from content scans. Existing mount-table
metadata was observed by the fleet diagnostic command.

### Verified state

| Item | Evidence | Implication |
| --- | --- | --- |
| Current and booted root | Both installed fstabs select the NVMe Btrfs `@` subvolume; `/home` is part of that root | Home already survives ordinary reboots. The draft also declares the whole `/home`, but the proposed initrd has not been exercised. |
| Root capacity | About 78 GiB available for data; only 1,052,672 bytes unallocated; metadata 72.52% used; global reserve unused; device error counters zero | The configured 10 GiB unallocated-space check fails. Investigate allocation pressure before migration; this observation does not establish corruption or an imminent failure. |
| NVMe tree accounting | `du -sx` reports about 843 GiB for `/home`, 100 GiB for `/nix`, and 16 GiB for `/var/lib` | A second complete copy does not fit on alpha. These are live filesystem-accounting figures, not a measured backup or restore size; compression, shared extents, hard links, and overlapping bind mounts affect them. |
| Large home categories | Games about 467 GiB; container torrents about 171 GiB | Do not silently classify these as disposable. Saves, mods, unique files, and resumable download state need an explicit retention decision before any recovery exclusion. |
| Latest daily snapshot | Offsite snapshot `f621dac1`, 2026-10-14 01:01 ART; backup unit completed successfully and its 5% read-data check passed | Covers exported container backups, Documents, Pictures, and selected staged config/local state. It does not prove full host recovery or an isolated application restore. |
| Credential presence | Host and user SSH identities, account databases, Codex auth, and the user Age file exist; private identity/auth files have mode 0600 | Presence and permissions were checked without reading credential contents. Complete recovery must retain these beyond the current daily allowlist. |
| Boot entries | Ten systemd-boot entries with readable kernel/initrd artifacts; configuration limit ten | An installed fallback is available, but no recovery boot was tested. Protect a known-good persistent-root generation and its closure from subsequent pruning before a trial. |
| Local recovery access | User confirms local console; rescue USB not tested; independent SSH/SOPS key stored but not tested | Boot the rescue USB and test the independent key before preparing the first tmpfs boot. |
| Epsilon restore destination | `/var/tmp` is tmpfs with about 5.7 GiB free; `/persist` has about 77 GiB disk-backed free | Neither is a destination for a complete alpha restore. Do not use the current helper's default `/var/tmp` restore location. |
| Other NVMe subvolumes | `/srv`, `/var/lib/machines`, and `/var/lib/portables` currently report zero usage; `@home` exists separately and is not the live home | Recheck before capture. Filesystem-boundary exclusions can skip nested Btrfs subvolumes; inventory them explicitly. Do not delete or reuse `@home` based on its name. |

Btrfs distinguishes unallocated device space from free space inside allocated
block groups. See the upstream [filesystem usage documentation](https://btrfs.readthedocs.io/en/latest/btrfs-filesystem.html#subcommand).
No balance, scrub, cleanup, or alert reset was run to change the observed state.

### Existing helper limitations

Do not enable the shared full-recovery helper unchanged for alpha. Its
filesystem list would include `/`, `/boot`, `/mnt/hdd`, and `/mnt/seagate`.
It also captures partition tables for all disks, assumes a host password
bootstrap secret that alpha does not declare, and restores into `/var/tmp`.
Those defaults conflict with this migration's scope or alpha's recovery needs.

A future alpha recovery implementation must explicitly select the NVMe root,
its retained subvolumes, and ESP; capture only `/dev/nvme0n1` partition metadata;
and require a disk-backed restore destination with adequate capacity. Account
recovery must verify the retained passwd/group/shadow databases rather than
assuming pi/epsilon's bootstrap-secret workflow applies unchanged.

### Required preparation sequence

1. Investigate the existing root-allocation health failure without changing
   the media disks. Establish a reviewed storage-health plan before taking a
   new large checkpoint or introducing a boot-layout change.
2. Choose an independent, adequately sized backup and isolated restore
   destination. HDD and Seagate are excluded as sources and destinations.
   Size it using a final recovery manifest and restore requirements. A local
   Btrfs snapshot may help undo a configuration change, but it is not an
   independent recovery copy for NVMe loss.
3. Define an NVMe-only recovery manifest. Include `/etc`, root/user identities,
   the whole home initially, complete container roots/configuration, and the
   boot/store metadata needed to return to the persistent-root generation.
   Explicitly exclude media bind mounts and cloud FUSE mounts; do not follow
   symlinks onto them. Include occupied nested NVMe subvolumes separately.
4. Plan application-consistent capture for Jellyfin, Prowlarr, qBittorrent,
   desktop/browser state, and T3 databases. Current daily SQLite staging is
   limited to its declared list. Decide which writers need a maintenance
   window or native export; do not stop production services merely to run
   this analysis.
5. Restore the captured state off-host into an isolated disk-backed tree.
   Verify numeric ownership, ACLs, xattrs, hard links, credential readability,
   account/identity manifests, and application database checks. Test SOPS
   decryption using the independently retrieved key with plaintext directed
   away from logs. Record the snapshot ID and the completed restore evidence.
6. Boot independently prepared rescue media at alpha's local console. Confirm
   NVMe/ESP visibility and ability to select the known-good persistent-root
   boot entry. Avoid mounting or operating on HDD and Seagate for this test.
7. Complete the disposable Btrfs VM trial, including missing-backing refusal,
   store/account mount ordering, nested media mount ordering, and fallback to
   the old persistent-root generation after the candidate has activated.
   Merely keeping an old entry does not prove fallback: both generations use
   the same mutable backing tree.

Only after these prerequisites pass should a separate reviewed boot candidate
and local-console maintenance window be prepared. The existing draft changes
no root layout and creates no readiness marker.

## Verification scope

`host-persistence` checks that alpha remains disabled, retains its Btrfs root,
creates no persistence mounts, and rejects enabling without the prepared boot
layout. The existing persistence VM tests shared identity and recovery
behavior on ext4. They do not prove this proposed Btrfs layout or alpha's
desktop and media services survive a volatile-root boot.

See the [shared persistence runbook](host-persistence.md),
[host recovery runbook](host-recovery.md), and
[configuration verification skill](../../.agents/skills/verify-nixos-config/SKILL.md).
