---
type: Runbook
title: Deploy NixOS to the Raspberry Pi (migration)
description: Install NixOS on the pi's SD card via nixos-anywhere, keeping the NVMe home disk and the Debian SSH host key.
when: Read when migrating the Raspberry Pi 5 from Debian to NixOS or reinstalling it.
resource: modules/hosts/pi.nix
tags: [runbook, pi, migration, nixos-anywhere, disko]
---

# Deploy NixOS to the Raspberry Pi

The pi boots NixOS from the SD card (`/dev/mmcblk0`). The NVMe
(`/dev/nvme0n1`) holds `/home/repparw` and is deliberately **not** part of the
disko config, so it is never touched by the installer. The SD layout is GPT
with pinned partition GUIDs, referenced from `fileSystems` in
`modules/hosts/pi.nix`.

## Prerequisites

1. Backups (run beforehand, kept in `~/backups/pi/`):
   - SD image: `pi-sd-2026-08-18.img`
   - NVMe state: `nvme-state-2026-08-18.tar.gz`
   - SSH host key: `ssh_host_ed25519_key.pi` / `ssh_host_ed25519_key.pub.pi`
2. The Debian host key must be copied into the new root before first boot:
   sops decrypts via `/etc/ssh/ssh_host_ed25519_key`, and the pi's sops
   recipient is derived from that exact key. Without it, `setupSecrets` fails
   and the first `nixos-rebuild` aborts.
3. A NixOS **aarch64 installer** must be booted manually first (USB stick or
   second SD): kexec does not work on the pi (its kernel has no
   `CONFIG_KEXEC_FILE`), so nixos-anywhere runs with `--phases
   disko,install,reboot`, skipping `kexec`.
4. alpha cannot build aarch64 (no binfmt emulation), so builds happen **on the
   installer** with `--build-on remote`.

## Deploy

```sh
# 1. Boot the NixOS aarch64 installer from USB, reachable at 192.168.0.4.
#    SSH must work (installer default: user nixos).

# 2. Stage the Debian SSH host key so sops can decrypt on first boot.
#    --extra-files copies recursively into the new root at /.
mkdir -p /tmp/pi-extra/etc/ssh
cp ~/backups/pi/ssh_host_ed25519_key.pi /tmp/pi-extra/etc/ssh/ssh_host_ed25519_key
cp ~/backups/pi/ssh_host_ed25519_key.pub.pi /tmp/pi-extra/etc/ssh/ssh_host_ed25519_key.pub

# 3. Install (run from the repo root on alpha).
nix run github:nix-community/nixos-anywhere -- \
  --flake '.#pi' \
  --target-host root@192.168.0.4 \
  --phases disko,install,reboot \
  --build-on remote \
  --extra-files /tmp/pi-extra
```

Notes:

- `--phases disko,install,reboot` skips `kexec` (installer already running).
- `--build-on remote` builds the aarch64 system and disko script on the
  installer, avoiding the need for binfmt on alpha.
- `disko` (default mode) destroys and recreates **only** the disks listed in
  the disko config (`/dev/mmcblk0`); `nvme0n1` stays untouched.
- The firmware partition's `postMountHook` installs u-boot, RPi firmware
  blobs, device trees, and `config.txt` (replicating nixpkgs'
  `sd-image-aarch64`), so the SD boots via EEPROM → u-boot → extlinux.

## First boot checks

```sh
ssh pi
sudo nixos-rebuild switch --flake '.#pi'
# Verify mounts, sops secrets, and the Home Assistant pod:
findmnt /home/repparw
sudo systemctl status sops-nix
systemctl --user status podservices-homeassistant
```

## Restore / rollback

- Full restore: `dd` the SD image back (`~/backups/pi/pi-sd-2026-08-18.img`)
  and re-extract the NVMe tar onto `/home/repparw`.
- The host key backup doubles as the sops key for the NixOS install.

## Related

- [Host profiles](../hosts.md)
- [Secrets](../agents/issue-tracker.md#secrets)