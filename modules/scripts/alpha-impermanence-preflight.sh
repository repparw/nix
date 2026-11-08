#!/usr/bin/env bash
# Read-only evidence for an Alpha Btrfs/root migration review.
# Does not create snapshots, touch the readiness marker, deploy, or reboot.
set -uo pipefail

show() {
  printf '\n###'
  printf ' %q' "$@"
  printf '\n'
  "$@" 2>&1 || printf 'Unavailable (exit %s)\n' "$?"
}

echo "alpha-impermanence-preflight (read-only)"
date --iso-8601=seconds
hostname
show uname -r
show lsblk -o NAME,FSTYPE,SIZE,UUID,MOUNTPOINTS
for path in / /boot /home /nix /srv /mnt/hdd /mnt/seagate; do
  show findmnt --target "$path" -o SOURCE,FSTYPE,FSROOT,TARGET,OPTIONS
done
show btrfs filesystem usage -b /
show btrfs device stats /
show btrfs subvolume list /
show df -B1 / /boot /nix /home
show swapon --show --output NAME,TYPE,SIZE,USED
show bootctl status
if [[ -d /srv ]]; then
  if [[ -n "$(find /srv -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    echo "/srv: NONEMPTY (stop and inventory separately)"
  else
    echo "/srv: empty or unreadable; verify permissions"
  fi
else
  echo "/srv: missing"
fi
if [[ -e /.host-persistence-ready || -e /persist/.host-persistence-ready ]]; then
  echo "WARNING: persistence readiness marker exists; verify before proceeding"
else
  echo "readiness marker: absent"
fi
echo "This output does not verify independent restore, rescue boot, or rollback."
