---
type: Runbook
title: Prepare alpha for a volatile root
description: Disabled persistence inventory, tested Btrfs mount behavior, and outstanding recovery gates for Alpha.
when: Read before enabling Alpha persistence, changing its storage layout, or reviewing its first volatile-root trial.
resource: modules/aspects/alpha-persistence.nix
tags: [alpha, impermanence, persistence, btrfs, recovery, desktop]
---

# Prepare alpha for a volatile root

Alpha's persistence inventory is disabled. Including it does not move files,
create `/persist`, or change the Btrfs root. Enabling persistence without a
prepared backing mount and tmpfs root fails evaluation.

## First migration scope

Retain the whole `/home`, `/var/lib`, and `/var/log`. This includes projects,
worktrees, AI credentials/databases, games and saves, container roots,
virtualization state, desktop device state, and operational records. Do not
classify unreviewed state as disposable during the first migration. The shared
aspect also retains `/etc` when mutable-account persistence is requested and
root's home. See [the inventory](../../modules/aspects/alpha-persistence.nix).

The previous directory allowlist omitted existing state and duplicated the
shared `/var/lib/host-recovery` entry. Retaining `/var/lib` avoids both problems;
shared early mounts for account allocation remain in place.

HDD and Seagate remain outside this migration. Do not format, repartition,
move data, change ownership, alter their mount declarations, or write recovery
backups to either disk. Exclude `/mnt/hdd`, `/mnt/seagate`, their media bind
mounts, and cloud FUSE mounts from capture or copy operations. Persistence bind
mounts reuse the existing NVMe directories; they do not copy mounted media.

## Proposed layout

Mount a tmpfs root and reuse the existing NVMe Btrfs `@` subvolume as `/persist`,
with explicit `subvol=@`. The separate `@home` subvolume is not Alpha's live
home. Bind `/persist/nix` to `/sysroot/nix` in the systemd initrd before
`initrd-nixos-activation.service`. Keep the store and database together.

Set `modules.persistence.mutableAccounts = true` to retain complete `/etc`
before account allocation. SOPS must read the prepared host key directly from
`/persist/etc/ssh`. Regenerate the random seed rather than installing a symlink
that becomes self-referential while `/` and `/persist` refer to the same tree.

The backing filesystem must be `neededForBoot`. Create the
`.host-persistence-ready` marker containing `alpha` only after the state and
recovery checks pass. The initrd guard rejects an absent or unprepared backing
volume. The existing `@` becomes durable backing state: never reset or delete it.

This draft declares no production backing mount or tmpfs-root boot candidate.

## Verification

`host-persistence` checks the disabled default, unchanged Btrfs root, absence of
persistence mounts, and refusal to enable an unprepared layout.

The disposable `host-persistence-btrfs-vm` uses the actual Alpha inventory and
shared persistence module. It seeds a Btrfs `@` root and an unrelated `@home`,
then exercises:

- Existing home and store-state reuse through `/persist` and the initrd `/nix` bind.
- A second tmpfs-root boot retaining SSH identity, changed passwords, and home data.
- A nested simulated media mount that remains separate from the backing home.
- Refusal to activate after the readiness marker is removed.

The test harness supplies executable Nix store content through its host share.
This does **not** prove an independently bootable NVMe store, ESP/bootloader
behavior, persistent-root fallback, physical rescue access, or desktop/container
application recovery. The existing ext4 persistence VM separately exercises
missing backing storage and offsite backup/restore behavior.

Run both VM checks and the evaluation check after changing this layout:

```bash
nix build .#checks.x86_64-linux.host-persistence \
  .#checks.x86_64-linux.host-persistence-vm \
  .#checks.x86_64-linux.host-persistence-btrfs-vm --no-link
```

## Live audit, 2026-10-21

Read-only storage inspection confirmed:

| Item                      | Observation                                                                                      | Consequence                                                                                                                          |
| ------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| Root and ESP              | NVMe `/dev/nvme0n1p2[/@]` is Btrfs; `/boot` is `/dev/nvme0n1p1`                                  | Home, store and service data remain on the original root.                                                                            |
| Capacity                  | About 68 GiB free; about 1 MiB unallocated; metadata 77.2% used; global reserve unused           | A second full copy does not fit. Review allocation pressure before a boot-layout change.                                             |
| Device errors             | All five Btrfs device error counters are zero                                                    | No reported device errors; this is not a full integrity or recovery test.                                                            |
| Other subvolumes          | `@home`, `srv`, `var/lib/machines`, `var/lib/portables`, `tmp`, `var/tmp`, and `.beeshome` exist | Inventory occupied subvolumes explicitly before capture; same-filesystem traversal can skip them. Do not delete them based on names. |
| Identity and boot entries | Machine ID, shadow and host SSH key present; ten installed boot entries                          | Presence does not prove independent key access or a working rescue/fallback boot.                                                    |
| Latest offsite attempt    | October 20 journal reports uploaded data but an incomplete `alpha-home` export                   | Do not treat the service's reset result after activation as proof of a successful backup.                                            |

The installed home exporter fails on the historical Bloodborne paths under
`.local/share/bbport-test/data/`. A synthetic reproduction confirmed rsync
returns `ELOOP` through that intermediate symlink. The draft instead selects
`Games/bbport/source/data/{bbport.ini,user/}` directly. The generated producer
passed a synthetic save/config capture and a one-off live NVMe export; its
completion marker was refreshed and the staged configuration matched the live
file. The installed scheduled unit still uses the old producer until activation.
A fresh offsite snapshot and isolated restore of the corrected export remain
unverified.

Earlier October 14 accounting estimated about 843 GiB in `/home`, 100 GiB in
`/nix`, and 16 GiB in `/var/lib`. These are dated filesystem-accounting figures,
not a measured backup size; compression, shared extents, nested filesystems,
and overlapping bind mounts affect them. No full scan was repeated on the media
disks. The ordinary daily backup remains a narrow allowlist, not full host
recovery coverage.

## Remaining gates before a production trial

1. Fix the home-export failure and verify a fresh offsite snapshot and isolated
   restore. Define a complete NVMe recovery manifest and an adequately sized,
   independent disk-backed destination. HDD and Seagate are excluded as both
   sources and destinations. Any exclusion of installed games, torrents or
   other home content needs an explicit retention decision; preserve unique
   saves, mods, credentials and resumable state.
2. Review the Btrfs allocation-health warning. Free space inside allocated
   block groups differs from unallocated device space. Do not run a balance or
   delete data just to silence the check. See the upstream
   [filesystem usage documentation](https://btrfs.readthedocs.io/en/latest/btrfs-filesystem.html#subcommand).
3. Test independently usable rescue media and the independently stored recovery
   key at Alpha's local console. Protect a known-good persistent-root generation
   and its closure from pruning.
4. Build a separate boot candidate and test its real store/ESP ordering and
   fallback to the old persistent-root generation. Both generations share
   mutable backing state; merely keeping an old boot entry does not prove recovery.
5. Schedule a local-console first boot outside automatic fleet deployment.
   Verify desktop login, networking, SOPS, existing passwords, credentials,
   container/application health, and a second reboot before making it default.

No production snapshot, restore, readiness marker, reboot or storage-layout
change was performed by this draft. The installed NVMe home-export service was retried and failed without replacing
its prior staging tree. The corrected candidate producer then completed a one-off
NVMe export through a transient systemd unit. No HDD sync job was run.
