set -x
exec >> /tmp/steam-sunshine.log 2>&1

echo "=== Starting Steam in Gamescope on DP-2 at $(date) ==="

# Ensure niri msg can find the socket
NIRI_SOCKET="$(systemctl --user show-environment | grep '^NIRI_SOCKET=' | cut -d= -f2-)"
export NIRI_SOCKET
if [ -z "$NIRI_SOCKET" ]; then
  echo "WARNING: NIRI_SOCKET not found in systemd user environment"
fi

# Kill any existing Steam or gamescope
pgrep -x steam >/dev/null 2>&1 && pkill -9 -x steam
pgrep -x gamescope >/dev/null 2>&1 && pkill -9 -x gamescope
sleep 4

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
for _ in $(seq 1 90); do
  sleep 0.5

  # Check if Steam died
  if ! kill -0 "$STEAM_PID" 2>/dev/null; then
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

    # Give Steam time to fully initialize its UI before we consider setup done
    echo "Waiting for Steam to initialize..."
    sleep 8

    break
  fi
done

if [ -z "$WINDOW_ID" ] || [ "$WINDOW_ID" = "null" ]; then
  echo "WARNING: No gamescope window found after timeout. Current windows:"
  niri msg --json windows | jq -c '.[] | {id, app_id, title}'
fi

# Wait for Steam to exit
wait "$STEAM_PID" 2>/dev/null || true
echo "Steam exited"
