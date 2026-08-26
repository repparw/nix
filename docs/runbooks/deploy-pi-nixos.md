---
type: Runbook
title: Deploy NixOS to the Raspberry Pi (migration)
description: Install NixOS on the pi's SD card via the official sd-image + nixos-anywhere, keeping the NVMe data disk (/nix + home) and the Debian SSH host key.
when: Read when migrating the Raspberry Pi 5 from Debian to NixOS or reinstalling it.
resource: modules/hosts/pi.nix
tags: [runbook, pi, migration, nixos-anywhere]
---

# Deploy NixOS to the Raspberry Pi

The pi boots NixOS from the internal SD card (`/dev/mmcblk0`). The second
drive (`/dev/nvme0n1`) holds data only and is never touched by the install:

- `/nix` — partition 1 (PARTUUID `7fd52c5b-01`, 40G)
- `/home/repparw` — partition 2 (PARTUUID `7fd52c5b-02`, 17.6G)

(roles swapped 2026-08-23 after the SD died; before that `-01` was home and
`-02` the store).

**This drive is not a real SSD.** It is the 64 GB module from an LCD-model
Steam Deck: FORESEE FE2H0M064G-B5X10 ("E2M2"), eMMC flash behind an O2 Micro
NVMe-to-eMMC bridge (PCI ID `1217:8760`). It enumerates as a genuine NVMe
namespace over PCIe Gen2 x1, which is why `/dev/nvme0n1` works, but it
performs at SD-card class (~250-350 MB/s seq read) and has eMMC-class
endurance. Known quirk: this bridge fails Pi 5 *boot* attempts in community
reports (bootloader error 8/10 loops), so treat any plan to move the boot
chain off the SD onto it with suspicion — see issue #41.

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
- The flashed image's dos table yields PARTUUIDs `2178694e-01`/`-02`; grow
  the root partition before installing anything (`sfdisk -N2 ... ,+` +
  online `resize2fs`) — the image base is only 3.6G.
- Inject SSH keys into the flashed card's `/home/nixos/.ssh/authorized_keys`
  and `/root/.ssh/authorized_keys` while it is in the card reader: the
  installer denies empty-password SSH.

## Gotchas hit during the 2026-08 migration

- **HA 2026.8 http config store**: Home Assistant persists its `http:`
  settings in `.storage/http` after the one-time yaml migration; later edits
  to `configuration.yaml` are ignored. When the podman graph root is wiped,
  the kube network subnet changes (10.89.1.0/24 -> 10.89.0.0/24) and HA
  starts rejecting proxied requests with "untrusted proxy" until the stored
  `trusted_proxies` is updated.
- **NixOS never changes a uid** of an existing user on switch
  (`update-users-groups.pl` keeps the old id). Get `users.users.<name>.uid`
  right before the user is first created, or delete the user record and
  rebuild to recreate it.
- **Quadlet over hand-written units**: `podman kube play` detaches, so a
  Type=simple unit exits instantly and ExecStop tears the pod down. Use a
  `.kube` quadlet (sd-notify wired correctly).
- After install, alpha's `known_hosts` holds the *installer's* host key;
  remove it once (`ssh-keygen -R`) — the installed system presents the
  preserved Debian key again.

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
