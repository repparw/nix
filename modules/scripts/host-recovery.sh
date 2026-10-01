#!/usr/bin/env bash
# Runtime paths and tools are supplied by modules/aspects/backup.nix.
set -euo pipefail
umask 077

if (( EUID != 0 )); then
  echo "host-recovery requires root to preserve account files and ownership" >&2
  exit 1
fi

recovery=/var/lib/host-recovery
install -d -m 0700 "$recovery"
restic_cmd=(restic -o "rclone.program=$(command -v rclone)")

case "${1:-}" in
  full|capture)
    if [[ $# -gt 2 || ( $# -eq 2 && ( $1 != full || $2 != --quiesce ) ) ]]; then
      echo "usage: host-recovery {full [--quiesce]|capture}" >&2
      exit 2
    fi
    exec 8>/run/host-recovery.lock
    flock -n 8
    exec 9>/run/fleet-update.lock
    flock -w 60 9
    mapfile -t paths < "$RECOVERY_PATHS_FILE"
    mapfile -t units < "$RECOVERY_UNITS_FILE"
    mapfile -t capture_paths < "$RECOVERY_CAPTURE_PATHS_FILE"
    restart=()
    cleanup() {
      local status=$?
      for unit in "${restart[@]}"; do
        systemctl start "$unit" || status=1
      done
      exit "$status"
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    tag=pre-impermanence-full-live
    if [[ $1 == capture || ${2:-} == --quiesce ]]; then
      tag=pre-impermanence-full-checkpoint
      for unit in "${units[@]}"; do
        if systemctl is-active --quiet "$unit"; then
          restart+=("$unit")
          systemctl stop "$unit"
        fi
      done
      if (( ${#capture_paths[@]} )); then
        # Preserve a consistent application copy while writers are stopped.
        # Restart immediately after the local copy, before the offsite transfer.
        tar --create --sparse --acls --xattrs --numeric-owner --file "$recovery/.application-state.new.tar" --directory / "${capture_paths[@]#/}"
        tar --compare --acls --xattrs --numeric-owner --file "$recovery/.application-state.new.tar" --directory /
        mv "$recovery/.application-state.new.tar" "$recovery/application-state.tar"
        (cd "$recovery"; sha256sum application-state.tar) > "$recovery/application-state.sha256"
        date --iso-8601=seconds > "$recovery/application-captured-at.txt"
      fi
      for unit in "${restart[@]}"; do
        systemctl start "$unit"
        systemctl is-active --quiet "$unit"
      done
      restart=()
    fi

    lsblk --json -b -O > "$recovery/lsblk.json"
    findmnt --json > "$recovery/findmnt.json"
    while IFS= read -r disk; do
      sfdisk --dump "$disk" > "$recovery/$(basename "$disk").sfdisk"
    done < <(lsblk --json -p -o NAME,TYPE,PTTYPE | jq -r '.blockdevices[] | select(.type == "disk" and .pttype != null) | .name')
    blkid > "$recovery/blkid.txt"
    readlink -f /run/current-system > "$recovery/current-system.txt"
    readlink -f /run/booted-system > "$recovery/booted-system.txt"
    cp "$RECOVERY_BOOTSTRAP_FILE" "$recovery/bootstrap.sops.yaml"
    cp "$RECOVERY_PATHS_FILE" "$recovery/filesystems.txt"
    cp "$RECOVERY_EXCLUDES_FILE" "$recovery/excludes.txt"
    printf '%s\n' "$tag" > "$recovery/snapshot-kind.txt"
    # Relative names let verification run inside a restored tree. Neither the
    # manifest nor the account hashes/key contents are printed to the terminal.
    (cd /; sha256sum etc/machine-id etc/ssh/ssh_host_ed25519_key etc/passwd etc/group etc/shadow) > "$recovery/identity.sha256"
    if [[ $1 == capture ]]; then
      echo "Local application checkpoint captured and verified; previously running services restarted."
      exit 0
    fi
    "${restic_cmd[@]}" backup --json --one-file-system --exclude-file "$RECOVERY_EXCLUDES_FILE" --tag "$tag" "${paths[@]}"
    ;;
  restore-check)
    if [[ $# != 2 || ! $2 =~ ^[a-fA-F0-9]{8,64}$ ]]; then
      echo "usage: host-recovery restore-check SNAPSHOT_ID (use RESTIC_REPOSITORY for another host)" >&2
      exit 2
    fi
    # Never restore into live paths. Retain the copy for inspection/recovery.
    restored=$(mktemp -d /var/tmp/host-recovery-restore.XXXXXX)
    printf 'Restoring into %s\n' "$restored"
    "${restic_cmd[@]}" restore "$2" --verify --target "$restored"
    (cd "$restored"; sha256sum --check --quiet var/lib/host-recovery/identity.sha256)
    keydir=$(mktemp -d /run/host-recovery-key.XXXXXX)
    trap 'rm -rf -- "$keydir"' EXIT
    ssh-to-age -private-key -i "$restored/etc/ssh/ssh_host_ed25519_key" > "$keydir/key"
    SOPS_AGE_KEY_FILE="$keydir/key" sops --decrypt "$restored/var/lib/host-recovery/bootstrap.sops.yaml" > /dev/null
    application_root="$restored"
    if [[ -f $restored/var/lib/host-recovery/application-state.tar ]]; then
      (cd "$restored/var/lib/host-recovery"; sha256sum --check --quiet application-state.sha256)
      application_root="$restored/application-checkpoint"
      mkdir -m 0700 "$application_root"
      tar --extract --acls --xattrs --numeric-owner --file "$restored/var/lib/host-recovery/application-state.tar" --directory "$application_root"
    fi
    hass="$application_root/home/repparw/services/hass"
    if [[ -d $hass ]]; then
      # A missing database must not look like a successful integrity check.
      database="$hass/home-assistant_v2.db"
      [[ -s $database ]] || { echo "Restored HA database is missing or empty" >&2; exit 1; }
      result=$(sqlite3 -readonly "$database" 'PRAGMA integrity_check;')
      [[ $result == ok ]] || { echo "Restored HA database failed integrity_check" >&2; exit 1; }
      echo "Restored HA database integrity_check passed."
    fi
    echo "Restic content verification, identity/account manifest and restored-host SOPS decryption passed."
    printf 'Restored files retained at %s\n' "$restored"
    ;;
  *)
    echo "usage: host-recovery {full [--quiesce]|capture|restore-check SNAPSHOT_ID}" >&2
    exit 2
    ;;
esac
