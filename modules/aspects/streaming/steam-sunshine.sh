set -x
exec >> /tmp/steam-sunshine.log 2>&1

echo "=== Starting Steam in Gamescope on DP-2 at $(date) ==="

# Kill any existing Steam or gamescope
pgrep -x steam >/dev/null 2>&1 && pkill -9 -x steam
pgrep -x gamescope >/dev/null 2>&1 && pkill -9 -x gamescope
sleep 2

# Start gamescope with Steam inside it on DP-2
# Gamescope handles game window management internally
gamescope \
  -W 2560 -H 1440 -r 120 \
  --steam \
  --force-grab-cursor \
  --adaptive-sync \
  -- steam -tenfoot -pipewire-dmabuf &
STEAM_PID=$!
echo "Steam/Gamescope PID: $STEAM_PID"

# Wait for gamescope window and move to DP-2
for i in {1..30}; do
  sleep 0.5

  # Check if Steam died
  if ! kill -0 $STEAM_PID 2>/dev/null; then
    echo "Steam process not found, checking for window anyway"
    break
  fi

  # Find gamescope window
  WINDOW_ID=$(niri msg --json windows | jq -r '.[] | select(.app_id == "gamescope" or (.title // "" | ascii_downcase | contains("gamescope"))) | .id' | head -1)

  if [ -n "$WINDOW_ID" ] && [ "$WINDOW_ID" != "null" ]; then
    echo "Found gamescope window $WINDOW_ID, moving to DP-2"
    niri msg action move-window-to-monitor DP-2 --id "$WINDOW_ID"
    sleep 0.5
    niri msg action focus-window --id "$WINDOW_ID"
    echo "Moved Gamescope to DP-2 and focused"

    # Wait for Steam to fully initialize before powering off monitors
    # Steam needs time to load the UI, otherwise it may exit
    echo "Waiting for Steam to initialize..."
    sleep 8

    # Power off all monitors via DPMS (doesn't affect output indices)
    niri msg action power-off-monitors
    echo "Powered off monitors"

    break
  fi
done

# Wait for Steam to exit
wait $STEAM_PID 2>/dev/null || true
echo "Steam exited"
