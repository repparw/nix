#!/usr/bin/env bash
set -euo pipefail

timeout_seconds="${SUNSHINE_IDLE_TIMEOUT_SECONDS:-600}"
check_interval_seconds="${SUNSHINE_IDLE_CHECK_INTERVAL_SECONDS:-15}"
watch_ports="${SUNSHINE_WATCH_PORTS:-47984 47989 47990 48010}"
cleanup_command="${SUNSHINE_CLEANUP_COMMAND:?SUNSHINE_CLEANUP_COMMAND is required}"

last_active="$(date +%s)"
seen_client=0
was_active=0
last_journal_check="$last_active"

has_active_client() {
  ss -Htan state established |
    awk -v ports="$watch_ports" '
      BEGIN {
        split(ports, port_list, " ")
        for (i in port_list) {
          wanted[":" port_list[i]] = 1
        }
      }
      {
        local_addr = $4
        for (port in wanted) {
          if (local_addr ~ port "$") {
            found = 1
          }
        }
      }
      END { exit(found ? 0 : 1) }
    '
}

while true; do
  now="$(date +%s)"
  recent_events="$(
    journalctl --user -u sunshine.service --since "@$last_journal_check" --no-pager 2>/dev/null |
      grep -E 'CLIENT CONNECTED|CLIENT DISCONNECTED' || true
  )"
  last_journal_check="$now"

  if printf '%s\n' "$recent_events" | grep -q 'CLIENT CONNECTED'; then
    seen_client=1
  fi

  if printf '%s\n' "$recent_events" | grep -q 'CLIENT DISCONNECTED'; then
    last_active="$now"
    seen_client=1
    if [ "$was_active" -eq 1 ]; then
      echo "Sunshine client disconnected; cleanup will run after ${timeout_seconds}s without a client."
    else
      echo "Sunshine client disconnect event detected; cleanup will run after ${timeout_seconds}s without a client."
    fi
    was_active=0
  fi

  if has_active_client; then
    if [ "$was_active" -eq 0 ]; then
      echo "Sunshine client connection detected."
    fi
    last_active="$(date +%s)"
    seen_client=1
    was_active=1
  elif [ "$was_active" -eq 1 ]; then
    echo "Sunshine client disconnected; cleanup will run after ${timeout_seconds}s without a client."
    was_active=0
  fi

  if [ "$seen_client" -eq 1 ] && [ "$((now - last_active))" -ge "$timeout_seconds" ]; then
    echo "No Sunshine client for ${timeout_seconds}s; running cleanup."
    "$cleanup_command" || true
    seen_client=0
  fi

  sleep "$check_interval_seconds"
done
