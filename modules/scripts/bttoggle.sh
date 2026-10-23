#!/usr/bin/env bash

device="${TOGGLE_BT_DEVICE:-$(cat /run/secrets/btDevice 2>/dev/null || true)}"
audio_sink="0000110b-0000-1000-8000-00805f9b34fb"
action="${1:-toggle}"

if [ -z "$device" ]; then
  echo "bttoggle: no device configured; set TOGGLE_BT_DEVICE or provision the btDevice secret" >&2
  exit 2
fi

info=$(bluetoothctl info "$device" 2>&1 || true)

is_connected() { [[ $info == *"Connected: yes"* ]]; }
is_blocked() { [[ $info == *"Blocked: yes"* ]]; }
refresh_info() { info=$(bluetoothctl info "$device" 2>&1 || true); }

block_quiet() { bluetoothctl block "$device" >/dev/null 2>&1 || true; }

do_connect() {
  bluetoothctl unblock "$device"
  if ! timeout 20 bluetoothctl connect "$device"; then
    exit 3
  fi

  audio_connected=false
  for _ in $(seq 1 10); do
    if timeout 20 bluetoothctl connect "$device" "$audio_sink"; then
      audio_connected=true
      break
    fi
    sleep 1
  done
  if ! $audio_connected; then
    exit 3
  fi

  refresh_info
  if ! is_connected; then
    exit 3
  fi
}

do_disconnect() {
  bluetoothctl disconnect "$device" >/dev/null 2>&1 || true
  block_quiet
}

case "$action" in
  connect)
    do_connect
    ;;
  disconnect)
    do_disconnect
    ;;
  toggle)
    if is_connected && ! is_blocked; then
      do_disconnect
    else
      do_connect
    fi
    ;;
  status)
    if is_connected; then connected=1; else connected=0; fi
    if is_blocked; then blocked=1; else blocked=0; fi
    printf '{"mac":"%s","blocked":%d,"connected":%d}\n' "$device" "$blocked" "$connected"
    ;;
  *)
    echo "Unknown action: $action. Use: connect|disconnect|toggle|status" >&2
    exit 1
    ;;
esac
