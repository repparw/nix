#!/usr/bin/env bash
set -x
exec >> /tmp/steam-sunshine.log 2>&1
connector_name="${SUNSHINE_CONNECTOR_NAME:-DP-2}"

# Pull session env from systemd so gamescope runs nested on Wayland
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

state_dir="${XDG_RUNTIME_DIR:-/tmp}/sunshine-stream"
mkdir -p "$state_dir"
date +%s > "$state_dir/managed-app-started"

GRAPHICAL_SESSION="$(loginctl --json=short 2>/dev/null | jq -r '[.[] | select(.seat != null and .seat != "-")] | first | .session' || true)"
if [ -n "$GRAPHICAL_SESSION" ] && [ "$GRAPHICAL_SESSION" != "null" ]; then
    loginctl unlock-session "$GRAPHICAL_SESSION"
fi

# Kill any existing Steam or gamescope
pgrep -x steam >/dev/null 2>&1 && pkill -9 -x steam
pgrep -x gamescope >/dev/null 2>&1 && pkill -9 -x gamescope
sleep 4

niri msg action focus-monitor "$connector_name"

gamemoderun gamescope \
    -H "$GAMESCOPE_HEIGHT" -r "$GAMESCOPE_REFRESH" \
    --steam \
    --force-grab-cursor \
    --adaptive-sync \
    -- env -u LD_PRELOAD bwrap \
    --dev-bind / / \
    --tmpfs /mnt/seagate \
    --tmpfs /home/containers/media/seagate \
    -- steam -tenfoot -pipewire-dmabuf &

niri msg action power-off-monitors
