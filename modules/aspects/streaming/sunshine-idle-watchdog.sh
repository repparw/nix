#!/usr/bin/env bash
set -euo pipefail

timeout_seconds="${SUNSHINE_IDLE_TIMEOUT_SECONDS:-600}"
check_interval_seconds="${SUNSHINE_IDLE_CHECK_INTERVAL_SECONDS:-15}"
cleanup_command="${SUNSHINE_CLEANUP_COMMAND:?SUNSHINE_CLEANUP_COMMAND is required}"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/sunshine-stream"
managed_app_marker="$state_dir/managed-app-started"

last_active="$(date +%s)"
seen_client=0
was_active=0
last_journal_check="$last_active"

recent_startup_event="$(
  journalctl --user -u sunshine.service --since "-24 hours" --no-pager 2>/dev/null |
    grep -E 'CLIENT CONNECTED|CLIENT DISCONNECTED' |
    tail -n 1 || true
)"

if printf '%s\n' "$recent_startup_event" | grep -q 'CLIENT CONNECTED'; then
  echo "Sunshine watchdog started while the latest recent client event is connected."
  seen_client=1
  was_active=1
elif printf '%s\n' "$recent_startup_event" | grep -q 'CLIENT DISCONNECTED'; then
  echo "Sunshine watchdog started after a recent client disconnect."
  seen_client=1
fi

while true; do
  now="$(date +%s)"
  recent_events="$(
    journalctl --user -u sunshine.service --since "@$last_journal_check" --no-pager 2>/dev/null |
      grep -E 'CLIENT CONNECTED|CLIENT DISCONNECTED' || true
  )"
  last_journal_check="$now"
  latest_event="$(printf '%s\n' "$recent_events" | tail -n 1)"

  if printf '%s\n' "$latest_event" | grep -q 'CLIENT CONNECTED'; then
    echo "Sunshine client connected."
    last_active="$now"
    seen_client=1
    was_active=1
  fi

  if printf '%s\n' "$latest_event" | grep -q 'CLIENT DISCONNECTED'; then
    last_active="$now"
    seen_client=1
    if [ "$was_active" -eq 1 ]; then
      echo "Sunshine client disconnected; cleanup will run after ${timeout_seconds}s without a client."
    else
      echo "Sunshine client disconnect event detected; cleanup will run after ${timeout_seconds}s without a client."
    fi
    was_active=0
  fi

  if [ "$seen_client" -eq 1 ] && [ "$was_active" -eq 0 ] && [ "$((now - last_active))" -ge "$timeout_seconds" ]; then
    echo "No Sunshine client for ${timeout_seconds}s; running cleanup."
    "$cleanup_command" || true
    seen_client=0
  fi

  if [ "$was_active" -eq 0 ] && [ -e "$managed_app_marker" ]; then
    marker_started="$(cat "$managed_app_marker" 2>/dev/null || stat -c %Y "$managed_app_marker" 2>/dev/null || echo "$now")"
    case "$marker_started" in
      ''|*[!0-9]*) marker_started="$now" ;;
    esac
    if [ "$((now - marker_started))" -ge "$timeout_seconds" ]; then
      echo "Sunshine launched app marker is stale with no connected client; running cleanup."
      "$cleanup_command" || true
      seen_client=0
      rm -f "$managed_app_marker"
    fi
  fi

  sleep "$check_interval_seconds"
done
