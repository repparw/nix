set -euo pipefail

case "${1:-}" in
  preflight)
    : "${RESTIC_FROM_REPOSITORY:?}"
    rclone about claro:
    rclone size "${RESTIC_FROM_REPOSITORY#rclone:}"
    ;;
  init|copy)
    : "${RESTIC_REPOSITORY:?}"
    : "${RESTIC_FROM_REPOSITORY:?}"
    : "${RESTIC_PASSWORD_FILE:?}"
    restic_args=(-o "rclone.program=${RCLONE_BIN:-rclone}")
    if [[ -n "${RESTIC_RCLONE_CONNECTIONS:-}" ]]; then
      restic_args+=(-o "rclone.connections=$RESTIC_RCLONE_CONNECTIONS")
    fi
    destination=(-r "$RESTIC_REPOSITORY" --password-file "$RESTIC_PASSWORD_FILE")
    source=(--from-repo "$RESTIC_FROM_REPOSITORY" --from-password-file "$RESTIC_PASSWORD_FILE")

    if [[ "$1" == init ]]; then
      exec restic "${restic_args[@]}" "${destination[@]}" init "${source[@]}" --copy-chunker-params
    fi

    upload_args=()
    if [[ -n "${RESTIC_UPLOAD_LIMIT_KIB:-}" ]]; then
      upload_args+=("--limit-upload=$RESTIC_UPLOAD_LIMIT_KIB")
    fi
    restic "${restic_args[@]}" "${destination[@]}" copy "${source[@]}" --retry-lock 30m "${upload_args[@]}"
    restic "${restic_args[@]}" "${destination[@]}" check --retry-lock 30m
    if [[ -n "${RESTIC_RETENTION_ARGS:-}" ]]; then
      read -r -a retention <<< "$RESTIC_RETENTION_ARGS"
      restic "${restic_args[@]}" "${destination[@]}" forget --prune --retry-lock 30m "${retention[@]}" "${upload_args[@]}"
    fi
    ;;
  *)
    echo "Usage: restic-claro-replica {preflight|init|copy}" >&2
    exit 2
    ;;
esac
