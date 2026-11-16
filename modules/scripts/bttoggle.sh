#!/usr/bin/env bash

device="${TOGGLE_BT_DEVICE:-$(cat /run/secrets/btDevice 2>/dev/null || true)}"
audio_sink="0000110b-0000-1000-8000-00805f9b34fb"
action="${1:-toggle}"

if [ -z "$device" ]; then
  echo "bttoggle: no device configured; set TOGGLE_BT_DEVICE or provision the btDevice secret" >&2
  exit 2
fi

is_connected() { [[ $(bluetoothctl info "$device" 2>/dev/null || true) == *"Connected: yes"* ]]; }

do_connect() {
  if ! timeout 20 bluetoothctl connect "$device"; then
    exit 3
  fi

  for _ in $(seq 1 10); do
    if timeout 20 bluetoothctl connect "$device" "$audio_sink"; then
      return
    fi
    sleep 1
  done
  exit 3
}

case "$action" in
  connect)
    do_connect
    ;;
  disconnect)
    bluetoothctl disconnect "$device"
    ;;
  toggle)
    if is_connected; then
      bluetoothctl disconnect "$device"
    else
      do_connect
    fi
    ;;
  status)
    if is_connected; then connected=1; else connected=0; fi
    printf '{"mac":"%s","connected":%d}\n' "$device" "$connected"
    ;;
  *)
    echo "Unknown action: $action. Use: connect|disconnect|toggle|status" >&2
    exit 1
    ;;
esac
