---
type: Runbook
title: Change host persistence
description: Boot constraints, storage-change prerequisites, and persistence verification.
when: Read before changing host persistence, updating its inventory, or reviewing persistence and recovery checks.
resource: modules/aspects/persistence.nix
tags: [impermanence, persistence, pi, epsilon, recovery, backups]
---

# Change host persistence

Pi and Epsilon use tmpfs roots backed by `/persist`; Alpha does not enable
persistence. The inventory and mount ordering live in
[persistence.nix](../../modules/aspects/persistence.nix), with additions in
[pi.nix](../../modules/hosts/pi.nix) and [epsilon.nix](../../modules/hosts/epsilon.nix).

## Preserve the boot and identity constraints

- `/persist` must be prepared and marked `neededForBoot`. The initrd requires
  the host's `.host-persistence-ready` marker, machine ID, SSH key, UID/GID state,
  and account database before activation. The guard detects unprepared storage,
  not an incomplete application copy.
- Both hosts enable `mutableAccounts`, retaining all of `/etc` before user
  activation. This preserves ordinary password changes. Individual account-file
  binds cannot accommodate atomic PAM/NixOS replacements
  ([Impermanence #120](https://github.com/nix-community/impermanence/issues/120)).
- SOPS reads `/persist/etc/ssh/ssh_host_ed25519_key` during early boot. Preserve
  that key; a replacement cannot decrypt secrets encrypted to the old identity.
  `/var/lib/nixos` must be available before allocating users.
- Pi requires its existing home NVMe in the initrd. Missing storage must stop
  boot rather than expose empty Home Assistant or user directories.
- Preserve full `/boot`, not just firmware or EFI partitions. Epsilon's GRUB
  uses the backing boot path and copied kernels for its persistent store layout.
- Epsilon retains `/var/lib/credential-remediation`; persisted service drop-ins
  depend on its helpers. Review that dependency before removing the directory.

Container roots, whole homes, and legacy archives beneath `/persist` remain
conservative preservation choices. They are not automatically disposable.
Persistence and offsite backup scope are separate; `/persist` itself is not a
blanket backup root.

## Prepare a storage change

1. Complete an [isolated restore](host-recovery.md). Inventory state outside
   daily scope and preserve an independent checkpoint before discarding it.
2. Test recovery credentials retrieved from storage outside the fleet. A restore
   using another running host does not prove recovery from losing all hosts.
3. Preserve the actual boot layout and prepare a working rescue boot or console.
   SSH cannot recover a failed initrd. A generation rollback cannot undo
   repartitioning or restore missing data.
4. Quiesce databases or use native exports. Copy state with numeric ownership,
   modes, ACLs, xattrs, and symlinks intact, including shifted container IDs.
   Preserve account files and verify password equality without printing hashes.
5. Verify backing data before writing `.host-persistence-ready` with the host
   name. Make the root-layout change outside automatic fleet deployment and
   verify service recovery before trialling another host.

For Alpha, first separate desktop and service state from the root subvolume.
Its `/home`, `/nix`, and application data currently share root subvolume `@`;
root rollback would encompass that data. An unmounted `@home` is not proof of
separation, and Prowlarr keeps live state in its container root.

## Verify changes

```sh
nix build .#checks.x86_64-linux.host-persistence --no-link
nix build .#checks.x86_64-linux.host-persistence-vm --no-link
```

The [evaluation checks](../../modules/_tests/host-persistence.nix) cover inventory,
account consent, mount ordering, and backup coverage. The
[VM test](../../modules/_tests/host-persistence-vm.nix) exercises passwords,
identity, SOPS, application state, incomplete exports, isolated restores, and
failed-boot recovery. It uses disposable x86 credentials and storage; real ARM
firmware, production services, device attachment, and interactive logins still
need their own validation. Use the [verification skill](../../.agents/skills/verify-nixos-config/SKILL.md)
for builds and the [fleet skill](../../.agents/skills/fleet-operations/SKILL.md)
for authorized activation.
