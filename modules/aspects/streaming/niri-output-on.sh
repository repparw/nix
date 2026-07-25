#!/usr/bin/env bash
connector_name="${SUNSHINE_CONNECTOR_NAME:-DP-2}"
output_mode="${SUNSHINE_OUTPUT_MODE:-3840x2160@120}"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/sunshine-stream"
wpaperd_marker="$state_dir/wpaperd-was-active"

NIRI_SOCKET="${NIRI_SOCKET:-$(systemctl --user show-environment | sed -n 's/^NIRI_SOCKET=//p' | head -n 1)}"
export NIRI_SOCKET

mkdir -p "$state_dir"

restore_after_error() {
  pkill -f "systemd-inhibit.*--who=Sunshine" 2>/dev/null || true
  if [ -e "$wpaperd_marker" ]; then
    systemctl --user start wpaperd.service || true
    rm -f "$wpaperd_marker"
  fi
}
trap restore_after_error ERR

# Unlock graphical session before streaming.
# swayidle's unlock event will kill swaylock.
GRAPHICAL_SESSION="$(loginctl --json=short 2>/dev/null | jq -r '[.[] | select(.seat != null and .seat != "-")] | first | .session' || true)"
if [ -n "$GRAPHICAL_SESSION" ] && [ "$GRAPHICAL_SESSION" != "null" ]; then
  loginctl unlock-session "$GRAPHICAL_SESSION"
fi

# Inhibit idle via logind so swayidle doesn't lock the session during stream.
# swayidle checks logind's BlockInhibited property, not Wayland idle inhibitors.
pkill -f "systemd-inhibit.*--who=Sunshine" 2>/dev/null || true
systemd-inhibit \
  --what=idle \
  --who=Sunshine \
  --why="Game streaming active" \
  --mode=block \
  sleep infinity &
disown

# wpaperd can draw through a stale Mesa context while outputs are hotplugged.
# Keep it stopped for the lifetime of the streaming output and restore it on reset.
if systemctl --user is-active --quiet wpaperd.service; then
  touch "$wpaperd_marker"
  systemctl --user stop wpaperd.service
fi

niri msg output "$connector_name" on
niri msg output "$connector_name" mode "$output_mode"

output_ready=0
for _ in $(seq 1 50); do
  if niri msg --json outputs | jq -e --arg name "$connector_name" \
    '.[] | select(.name == $name and .current_mode != null and .logical != null)' >/dev/null; then
    output_ready=1
    break
  fi
  sleep 0.1
done

if [ "$output_ready" -ne 1 ]; then
  echo "Output $connector_name did not become ready" >&2
  exit 1
fi

# Let Wayland, Mesa, and the DRM encoder observe a stable output before Sunshine probes.
sleep 2
trap - ERR
