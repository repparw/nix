#!/usr/bin/env bash
set -euo pipefail

script="$1"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
date_calls="$test_dir/date-calls"
cleanup_calls="$test_dir/cleanup-calls"
printf '0\n' > "$date_calls"
printf '0\n' > "$cleanup_calls"

date() {
  calls="$(< "$date_calls")"
  if [ "$calls" -eq 0 ]; then
    printf '100\n'
  else
    printf '110\n'
  fi
  printf '%s\n' "$((calls + 1))" > "$date_calls"
}

journalctl() {
  case " $* " in
    *" --since -24 hours "*)
      printf '%s\n' \
        'Jan 01 00:00:00 host sunshine[1]: CLIENT DISCONNECTED' \
        '-- cursor: first'
      ;;
    *" --after-cursor=first "*)
      printf '%s\n' '-- cursor: first'
      ;;
    *)
      echo "unexpected journalctl invocation: $*" >&2
      return 1
      ;;
  esac
}

cleanup() {
  calls="$(< "$cleanup_calls")"
  printf '%s\n' "$((calls + 1))" > "$cleanup_calls"
}

export XDG_RUNTIME_DIR="$test_dir/runtime"
export SUNSHINE_IDLE_TIMEOUT_SECONDS=10
export SUNSHINE_IDLE_CHECK_INTERVAL_SECONDS=1
export SUNSHINE_IDLE_MAX_CHECKS=1
export SUNSHINE_CLEANUP_COMMAND=cleanup

# A disconnect found during startup must age from its original observation.
# Re-reading that same journal entry would reset the timer and suppress cleanup forever.
# shellcheck source=/dev/null
source "$script" > "$test_dir/output"

if [ "$(< "$cleanup_calls")" -ne 1 ]; then
  echo "expected exactly one cleanup after an idle startup disconnect" >&2
  exit 1
fi
if ! grep -q 'No Sunshine client for 10s; running cleanup.' "$test_dir/output"; then
  echo "expected timeout cleanup log entry" >&2
  exit 1
fi

if (
  export SUNSHINE_IDLE_TIMEOUT_SECONDS=invalid
  # shellcheck source=/dev/null
  source "$script"
) > "$test_dir/invalid-output" 2>&1; then
  echo "invalid timeout unexpectedly succeeded" >&2
  exit 1
fi
if ! grep -q 'must be non-negative integers' "$test_dir/invalid-output"; then
  echo "invalid timeout did not produce a useful error" >&2
  exit 1
fi
