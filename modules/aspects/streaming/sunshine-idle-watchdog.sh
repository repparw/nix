#!/usr/bin/env bash
set -euo pipefail

timeout_seconds="${SUNSHINE_IDLE_TIMEOUT_SECONDS:-600}"
check_interval_seconds="${SUNSHINE_IDLE_CHECK_INTERVAL_SECONDS:-15}"
cleanup_command="${SUNSHINE_CLEANUP_COMMAND:?SUNSHINE_CLEANUP_COMMAND is required}"
max_checks="${SUNSHINE_IDLE_MAX_CHECKS:-0}"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/sunshine-stream"
managed_app_marker="$state_dir/managed-app-started"

case "$timeout_seconds:$max_checks" in
  *[!0-9:]*)
    echo "SUNSHINE_IDLE_TIMEOUT_SECONDS and SUNSHINE_IDLE_MAX_CHECKS must be non-negative integers" >&2
    exit 2
    ;;
esac

last_active="$(date +%s)"
seen_client=0
was_active=0
checks=0

startup_journal="$(journalctl --user -u sunshine.service --since "-24 hours" --no-pager --show-cursor 2>/dev/null || true)"
journal_cursor="$(printf '%s\n' "$startup_journal" | sed -n 's/^-- cursor: //p' | tail -n 1)"
recent_startup_event="$(printf '%s\n' "$startup_journal" | grep -E 'CLIENT CONNECTED|CLIENT DISCONNECTED' | tail -n 1 || true)"

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
  if [ -n "$journal_cursor" ]; then
    journal_output="$(journalctl --user -u sunshine.service --after-cursor="$journal_cursor" --no-pager --show-cursor 2>/dev/null || true)"
  else
    journal_output="$(journalctl --user -u sunshine.service --since "@$now" --no-pager --show-cursor 2>/dev/null || true)"
  fi
  next_cursor="$(printf '%s\n' "$journal_output" | sed -n 's/^-- cursor: //p' | tail -n 1)"
  if [ -n "$next_cursor" ]; then
    journal_cursor="$next_cursor"
  fi
  recent_events="$(printf '%s\n' "$journal_output" | grep -E 'CLIENT CONNECTED|CLIENT DISCONNECTED' || true)"
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

  checks=$((checks + 1))
  if [ "$max_checks" -gt 0 ] && [ "$checks" -ge "$max_checks" ]; then
    break
  fi

  sleep "$check_interval_seconds"
done
