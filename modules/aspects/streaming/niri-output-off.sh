#!/usr/bin/env bash
connector_name="${SUNSHINE_CONNECTOR_NAME:-DP-2}"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/sunshine-stream"
wpaperd_marker="$state_dir/wpaperd-was-active"

if [ -z "${NIRI_SOCKET:-}" ]; then
  eval "$(systemctl --user show-environment | grep '^NIRI_SOCKET=' || true)"
  export NIRI_SOCKET
fi

mkdir -p "$state_dir"

# If cleanup runs without the normal prepare hook, still protect wpaperd from
# the connector disappearing underneath its Mesa context.
if systemctl --user is-active --quiet wpaperd.service; then
  touch "$wpaperd_marker"
  systemctl --user stop wpaperd.service
fi

for process_name in gamescope steam heroic; do
  pkill -TERM -x "$process_name" 2>/dev/null || true
done

for _ in $(seq 1 30); do
  if ! pgrep -x gamescope >/dev/null 2>&1 \
    && ! pgrep -x steam >/dev/null 2>&1 \
    && ! pgrep -x heroic >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

for process_name in gamescope steam heroic; do
  pkill -KILL -x "$process_name" 2>/dev/null || true
done

niri msg output "$connector_name" off || true
pkill -f "systemd-inhibit.*--who=Sunshine" 2>/dev/null || true

# Avoid recreating a GL context until the output removal has propagated.
sleep 2
if [ -e "$wpaperd_marker" ]; then
  systemctl --user start wpaperd.service
  rm -f "$wpaperd_marker"
fi
