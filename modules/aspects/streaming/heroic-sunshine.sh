#!/usr/bin/env bash
set -x
exec >> /tmp/heroic-sunshine.log 2>&1

while IFS='=' read -r key value; do
    case "$key" in
        NIRI_SOCKET|WAYLAND_DISPLAY|DISPLAY|XDG_RUNTIME_DIR)
            export "$key=$value"
            ;;
    esac
done < <(systemctl --user show-environment)

if [ -z "$NIRI_SOCKET" ]; then
    echo "WARNING: NIRI_SOCKET not found in systemd user environment"
fi
if [ -z "$WAYLAND_DISPLAY" ]; then
    echo "WARNING: WAYLAND_DISPLAY not set, gamescope may fail"
fi

GRAPHICAL_SESSION="$(loginctl --json=short 2>/dev/null | jq -r '[.[] | select(.seat != null and .seat != "-")] | first | .session' || true)"
if [ -n "$GRAPHICAL_SESSION" ] && [ "$GRAPHICAL_SESSION" != "null" ]; then
    loginctl unlock-session "$GRAPHICAL_SESSION"
fi

pgrep -x gamescope >/dev/null 2>&1 && pkill -9 -x gamescope
sleep 2

niri msg action focus-monitor DP-2

gamescope \
    -H "$GAMESCOPE_HEIGHT" -r "$GAMESCOPE_REFRESH" \
    --force-grab-cursor \
    --adaptive-sync \
    -- heroic --console &

niri msg action power-off-monitors
