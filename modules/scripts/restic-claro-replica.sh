#!/usr/bin/env bash
set -euo pipefail

: "${RESTIC_REPOSITORY:?}"
: "${RESTIC_FROM_REPOSITORY:?}"
: "${RESTIC_PASSWORD_FILE:?}"

if [[ "$RESTIC_REPOSITORY" != rclone:claro:* || "$RESTIC_FROM_REPOSITORY" != rclone:* ]]; then
  echo "Unexpected Restic repository configuration" >&2
  exit 1
fi

source_remote="${RESTIC_FROM_REPOSITORY#rclone:}"
target_remote="${RESTIC_REPOSITORY#rclone:}"

case "${1:-}" in
  preflight)
    rclone about claro: --json
    rclone size "$source_remote" --json
    ;;
  copy)
    restic_args=(-o "rclone.program=${RCLONE_BIN:-rclone}")
    prune_args=("${restic_args[@]}")
    if [[ -n "${RESTIC_RCLONE_CONNECTIONS:-}" ]]; then
      restic_args+=(-o "rclone.connections=$RESTIC_RCLONE_CONNECTIONS")
      # Pruning requires at least two backend connections.
      if [[ "$RESTIC_RCLONE_CONNECTIONS" == 1 ]]; then
        prune_args+=(-o "rclone.connections=2")
      else
        prune_args+=(-o "rclone.connections=$RESTIC_RCLONE_CONNECTIONS")
      fi
    fi
    destination=(-r "$RESTIC_REPOSITORY" --password-file "$RESTIC_PASSWORD_FILE")
    source=(--from-repo "$RESTIC_FROM_REPOSITORY" --from-password-file "$RESTIC_PASSWORD_FILE")

    # The destination is private to this host. Never overwrite another repo.
    rclone mkdir "$target_remote"
    listing=$(rclone lsf "$target_remote")
    if grep -Fxq config <<< "$listing"; then
      : # Existing repository: Restic verifies the key before copying.
    elif [[ -n "$listing" ]]; then
      echo "Claro destination is nonempty but has no Restic config; refusing to initialize" >&2
      exit 1
    else
      # Only the first initialization needs room for a full copy. Leave a GiB
      # for the account's other files and Restic's metadata.
      quota=$(rclone about claro: --json)
      sizes=$(rclone size "$source_remote" --json)
      free=$(jq -er '.free | select(type == "number") | floor' <<< "$quota") || {
        echo "Claro did not report free quota; refusing first replication" >&2
        exit 1
      }
      bytes=$(jq -er '.bytes | select(type == "number") | floor' <<< "$sizes")
      if (( bytes > free - 1073741824 )); then
        echo "Claro has insufficient space for the initial Restic mirror" >&2
        exit 1
      fi
      restic "${restic_args[@]}" "${destination[@]}" init "${source[@]}" --copy-chunker-params
    fi

    upload_args=()
    if [[ -n "${RESTIC_UPLOAD_LIMIT_KIB:-}" ]]; then
      upload_args+=("--limit-upload=$RESTIC_UPLOAD_LIMIT_KIB")
    fi
    restic "${restic_args[@]}" "${destination[@]}" copy "${source[@]}" --retry-lock 30m "${upload_args[@]}"
    restic "${restic_args[@]}" "${destination[@]}" check --retry-lock 30m
    if [[ -n "${RESTIC_RETENTION_ARGS:-}" ]]; then
      read -r -a retention <<< "$RESTIC_RETENTION_ARGS"
      restic "${prune_args[@]}" "${destination[@]}" forget --prune --retry-lock 30m "${retention[@]}" "${upload_args[@]}"
      restic "${restic_args[@]}" "${destination[@]}" check --retry-lock 30m
    fi
    ;;
  *)
    echo "Usage: restic-claro-replica {preflight|copy}" >&2
    exit 2
    ;;
esac
