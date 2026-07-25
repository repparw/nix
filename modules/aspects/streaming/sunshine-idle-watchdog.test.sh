#!/usr/bin/env bash
# The test intentionally generates a mock script from literal shell source and
# invokes functions indirectly by sourcing the watchdog in subshells.
# shellcheck disable=SC2016,SC2030,SC2031,SC2329
set -euo pipefail

script="$1"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
event_command="$test_dir/latest-event"

printf '%s\n' \
  "#!$BASH" \
  'set -euo pipefail' \
  'calls="$(< "$EVENT_CALLS_FILE")"' \
  'printf "%s\n" "$((calls + 1))" > "$EVENT_CALLS_FILE"' \
  'case "$EVENT_MODE:$calls" in' \
  '  disconnected:*) printf "%s\n" "[2026-01-01 00:00:00]: Info: CLIENT DISCONNECTED" ;;' \
  '  connected:*) printf "%s\n" "[2026-01-01 00:00:00]: Info: CLIENT CONNECTED" ;;' \
  '  reconnect:0) printf "%s\n" "[2026-01-01 00:00:00]: Info: CLIENT DISCONNECTED" ;;' \
  '  reconnect:*) printf "%s\n" "[2026-01-01 00:00:01]: Info: CLIENT CONNECTED" ;;' \
  '  unavailable:*) exit 1 ;;' \
  'esac' > "$event_command"
chmod +x "$event_command"

run_case() {
  case_name="$1"
  event_mode="$2"
  expect_cleanup="$3"
  runtime_dir="$test_dir/$case_name/runtime"
  output="$test_dir/$case_name/output"
  date_calls="$test_dir/$case_name/date-calls"
  cleanup_calls="$test_dir/$case_name/cleanup-calls"
  event_calls="$test_dir/$case_name/event-calls"
  mkdir -p "$runtime_dir/sunshine-stream"
  printf '90\n' > "$runtime_dir/sunshine-stream/managed-app-started"
  printf '0\n' > "$date_calls"
  printf '0\n' > "$cleanup_calls"
  printf '0\n' > "$event_calls"

  (
    date() {
      calls="$(< "$date_calls")"
      if [ "$calls" -eq 0 ]; then
        printf '100\n'
      else
        printf '110\n'
      fi
      printf '%s\n' "$((calls + 1))" > "$date_calls"
    }

    cleanup() {
      calls="$(< "$cleanup_calls")"
      printf '%s\n' "$((calls + 1))" > "$cleanup_calls"
    }

    export EVENT_CALLS_FILE="$event_calls"
    export EVENT_MODE="$event_mode"
    export XDG_RUNTIME_DIR="$runtime_dir"
    export SUNSHINE_IDLE_TIMEOUT_SECONDS=10
    export SUNSHINE_IDLE_CHECK_INTERVAL_SECONDS=1
    export SUNSHINE_IDLE_MAX_CHECKS=1
    export SUNSHINE_CLEANUP_COMMAND=cleanup
    export SUNSHINE_CLIENT_EVENT_COMMAND="$event_command"

    # shellcheck source=/dev/null
    source "$script"
  ) > "$output"

  if [ "$(< "$cleanup_calls")" -ne "$expect_cleanup" ]; then
    echo "$case_name: expected $expect_cleanup cleanup call(s)" >&2
    cat "$output" >&2
    exit 1
  fi
}

run_case disconnected disconnected 1
if ! grep -q 'No Sunshine client for 10s; running cleanup.' "$test_dir/disconnected/output"; then
  echo "expected timeout cleanup after a verified disconnect" >&2
  exit 1
fi

run_case connected connected 0
run_case reconnect reconnect 0
run_case unavailable unavailable 0
if ! grep -q 'cleanup is suspended' "$test_dir/unavailable/output"; then
  echo "expected fail-safe behavior when Sunshine state is unavailable" >&2
  exit 1
fi

if (
  export SUNSHINE_IDLE_TIMEOUT_SECONDS=invalid
  export SUNSHINE_CLEANUP_COMMAND=true
  export SUNSHINE_CLIENT_EVENT_COMMAND=true
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
