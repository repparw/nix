#!/usr/bin/env bash
connector_name="${SUNSHINE_CONNECTOR_NAME:-DP-2}"

NIRI_SOCKET="${NIRI_SOCKET:-$(systemctl --user show-environment | sed -n 's/^NIRI_SOCKET=//p' | head -n 1)}"
export NIRI_SOCKET

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

niri msg output "$connector_name" on
