#!/usr/bin/env bash
set -x
connector_name="${SUNSHINE_CONNECTOR_NAME:-DP-2}"
sunshine_prepare_launch heroic

pgrep -x gamescope >/dev/null 2>&1 && pkill -9 -x gamescope
sleep 2

niri msg action focus-monitor "$connector_name"

gamemoderun gamescope \
    -H "$GAMESCOPE_HEIGHT" -r "$GAMESCOPE_REFRESH" \
    --force-grab-cursor \
    --adaptive-sync \
    -- heroic --console &

niri msg action power-off-monitors
