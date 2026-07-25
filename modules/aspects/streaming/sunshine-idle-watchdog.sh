#!/usr/bin/env bash
set -euo pipefail

timeout_seconds="${SUNSHINE_IDLE_TIMEOUT_SECONDS:-600}"
check_interval_seconds="${SUNSHINE_IDLE_CHECK_INTERVAL_SECONDS:-15}"
cleanup_command="${SUNSHINE_CLEANUP_COMMAND:?SUNSHINE_CLEANUP_COMMAND is required}"
client_event_command="${SUNSHINE_CLIENT_EVENT_COMMAND:?SUNSHINE_CLIENT_EVENT_COMMAND is required}"
max_checks="${SUNSHINE_IDLE_MAX_CHECKS:-0}"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/sunshine-stream"
managed_app_marker="$state_dir/managed-app-started"

case "$timeout_seconds:$max_checks" in
  *[!0-9:]*)
    echo "SUNSHINE_IDLE_TIMEOUT_SECONDS and SUNSHINE_IDLE_MAX_CHECKS must be non-negative integers" >&2
    exit 2
    ;;
esac

latest_client_event() {
  event_output=""
  if ! event_output="$("$client_event_command" 2>/dev/null)"; then
    return 1
  fi
  printf '%s\n' "$event_output" | grep -E 'CLIENT CONNECTED|CLIENT DISCONNECTED' | tail -n 1 || true
}

now="$(date +%s)"
last_active="$now"
last_event=""
seen_client=0
was_active=0
client_state_known=0
checks=0

if startup_event="$(latest_client_event)"; then
  client_state_known=1
  last_event="$startup_event"
  if printf '%s\n' "$startup_event" | grep -q 'CLIENT CONNECTED'; then
    echo "Sunshine watchdog started while the latest client event is connected."
    seen_client=1
    was_active=1
  elif printf '%s\n' "$startup_event" | grep -q 'CLIENT DISCONNECTED'; then
    echo "Sunshine watchdog started after the latest client disconnect."
    seen_client=1
  fi
else
  echo "Sunshine client state is unavailable; cleanup is suspended until it can be verified."
fi

while true; do
  now="$(date +%s)"

  if current_event="$(latest_client_event)"; then
    client_state_known=1
    if [ -n "$current_event" ] && [ "$current_event" != "$last_event" ]; then
      last_event="$current_event"
      last_active="$now"
      seen_client=1

      if printf '%s\n' "$current_event" | grep -q 'CLIENT CONNECTED'; then
        echo "Sunshine client connected."
        was_active=1
      elif printf '%s\n' "$current_event" | grep -q 'CLIENT DISCONNECTED'; then
        echo "Sunshine client disconnected; cleanup will run after ${timeout_seconds}s without a client."
        was_active=0
      fi
    fi
  else
    client_state_known=0
  fi

  if [ "$client_state_known" -eq 1 ] && [ "$was_active" -eq 0 ] && [ -e "$managed_app_marker" ]; then
    marker_started="$(cat "$managed_app_marker" 2>/dev/null || stat -c %Y "$managed_app_marker" 2>/dev/null || echo "$now")"
    case "$marker_started" in
      ''|*[!0-9]*) marker_started="$now" ;;
    esac

    idle_since="$marker_started"
    if [ "$seen_client" -eq 1 ] && [ "$last_active" -gt "$idle_since" ]; then
      idle_since="$last_active"
    fi

    if [ "$((now - idle_since))" -ge "$timeout_seconds" ]; then
      if [ "$seen_client" -eq 1 ]; then
        echo "No Sunshine client for ${timeout_seconds}s; running cleanup."
      else
        echo "Sunshine launched an app but no client connected for ${timeout_seconds}s; running cleanup."
      fi
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
