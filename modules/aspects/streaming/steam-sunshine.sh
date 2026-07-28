#!/usr/bin/env bash
set -x
connector_name="${SUNSHINE_CONNECTOR_NAME:-DP-2}"
sunshine_prepare_launch steam

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
