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

HDD and Seagate media are mounted below `/home/containers/media` from separate
disks. Keep those filesystem declarations and their existing bind mounts.
Preserve numeric owners, ACLs, extended attributes, and container UID mappings.

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
   declarations are not backups. Do not enable broad offsite backup blindly:
   decide how to cover the large download and media trees first.
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

## Verification scope

`host-persistence` checks that alpha remains disabled, retains its Btrfs root,
creates no persistence mounts, and rejects enabling without the prepared boot
layout. The existing persistence VM tests shared identity and recovery
behavior on ext4. They do not prove this proposed Btrfs layout or alpha's
desktop and media services survive a volatile-root boot.

See the [shared persistence runbook](host-persistence.md),
[host recovery runbook](host-recovery.md), and
[configuration verification skill](../../.agents/skills/verify-nixos-config/SKILL.md).
