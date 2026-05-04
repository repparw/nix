#!/usr/bin/env bash
set -x
exec >> /tmp/steam-sunshine.log 2>&1

# Ensure niri msg can find the socket
NIRI_SOCKET="$(systemctl --user show-environment | grep '^NIRI_SOCKET=' | cut -d= -f2-)"
export NIRI_SOCKET
if [ -z "$NIRI_SOCKET" ]; then
    echo "WARNING: NIRI_SOCKET not found in systemd user environment"
fi

GRAPHICAL_SESSION="$(loginctl --json=short 2>/dev/null | jq -r '[.[] | select(.seat != null and .seat != "-")] | first | .session' || true)"
if [ -n "$GRAPHICAL_SESSION" ] && [ "$GRAPHICAL_SESSION" != "null" ]; then
    loginctl unlock-session "$GRAPHICAL_SESSION"
fi

# Kill any existing Steam or gamescope
pgrep -x steam >/dev/null 2>&1 && pkill -9 -x steam
pgrep -x gamescope >/dev/null 2>&1 && pkill -9 -x gamescope
sleep 4

niri msg action focus-monitor DP-2

gamescope \
    -H "$GAMESCOPE_HEIGHT" -r "$GAMESCOPE_REFRESH" \
    --steam \
    --force-grab-cursor \
    --adaptive-sync \
    -- steam -tenfoot -pipewire-dmabuf &

niri msg action power-off-monitors
