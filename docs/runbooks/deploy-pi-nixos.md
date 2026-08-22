---
type: Runbook
title: Deploy NixOS to the Raspberry Pi (migration)
description: Install NixOS on the pi's SD card via the official sd-image + nixos-anywhere, keeping the NVMe home disk and the Debian SSH host key.
when: Read when migrating the Raspberry Pi 5 from Debian to NixOS or reinstalling it.
resource: modules/hosts/pi.nix
tags: [runbook, pi, migration, nixos-anywhere]
---

# Deploy NixOS to the Raspberry Pi

The pi boots NixOS from the internal SD card (`/dev/mmcblk0`). The NVMe
(`/dev/nvme0n1`) holds `/home/repparw` and is never touched by the install.

USB-booting an installer image hard-hangs this board's bootloader (even on the
2026-05 EEPROM), so the installer runs **from the internal SD** instead, and
NixOS is installed over the running installer root without reformatting.

## Prerequisites

1. Backups (in `~/backups/pi/`):
   - SD image: `pi-sd-2026-08-18.img`
   - NVMe state: `nvme-state-2026-08-18.tar.gz`
   - SSH host key: `ssh_host_ed25519_key.pi` / `.pub.pi` — sops decrypts via
     this key; without it the first activation fails.
2. The generic NixOS aarch64 sd-image from **nixos-unstable** (stable images
   lack Pi-5-family boot files):
   https://hydra.nixos.org/job/nixos/unstable/nixos.sd_image.aarch64-linux/latest

## Install

```sh
# 1. Flash the installer image onto the SD card (card reader on alpha).
zstdcat ~/backups/pi/installer/nixos-sd-aarch64-unstable.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync status=none

# 2. Read the resulting PARTUUIDs (dos table) and make sure fileSystems in
#    modules/hosts/pi.nix reference them.
sudo blkid /dev/sdX*

# 3. Move the SD back into the pi and power on. The installer boots from SD
#    (EEPROM BOOT_ORDER=0xf614: USB -> SD -> NVMe) and requests DHCP.

# 4. Find its address, then inject SSH access (installer denies empty passwords):
ssh-keyscan <ip> 2>/dev/null # reachability check
# authorized_keys were pre-injected when flashing (see below).

# 5. From the repo root on alpha: bind-mount the live root at /mnt and run
#    nixos-anywhere WITHOUT the disko phase (same-partition install).
ssh root@<ip> 'mkdir -p /mnt && mount --bind / /mnt'
mkdir -p /tmp/pi-extra/etc/ssh
cp ~/backups/pi/ssh_host_ed25519_key.pi    /tmp/pi-extra/etc/ssh/ssh_host_ed25519_key
cp ~/backups/pi/ssh_host_ed25519_key.pub.pi /tmp/pi-extra/etc/ssh/ssh_host_ed25519_key.pub

nix run github:nix-community/nixos-anywhere -- \
  --flake '.#pi' \
  --target-host root@<ip> \
  --phases install,reboot \
  --build-on remote \
  --extra-files /tmp/pi-extra
```

Notes:

- `--phases install,reboot` skips both kexec (unsupported kernel) and disko
  (would wipe the running root); `--build-on remote` builds aarch64 on the pi
  itself since alpha has no binfmt emulation.
- Installing over the live root leaves orphaned installer files in `/`;
  they are inert and can be pruned later.
- The firmware partition ships with the image (u-boot, bcm2712 dtbs,
  config.txt with `[pi5] enable_uart=0`) — nothing to provision manually.

## First boot checks

```sh
ssh pi
findmnt /home/repparw
sudo systemctl status sops-nix
systemctl --user status podservices-homeassistant
```

If the root filesystem is smaller than the card (3.6G image base), grow it:
`sudo growpart /dev/mmcblk0 2 && sudo resize2fs /dev/mmcblk0p2` (or reboot
first — the sd-image grows the root partition on first boot automatically).

## Restore / rollback

- Full restore: `dd` the SD image back (`~/backups/pi/pi-sd-2026-08-18.img`)
  and re-extract the NVMe tar onto `/home/repparw`.
- The host key backup doubles as the sops key for the NixOS install.

## Related

- [Host profiles](../hosts.md)
