#!/usr/bin/env bash
NIRI_SOCKET="${NIRI_SOCKET:-$(systemctl --user show-environment | sed -n 's/^NIRI_SOCKET=//p' | head -n 1)}"
export NIRI_SOCKET

# Unlock graphical session before streaming.
# swayidle's unlock event will kill swaylock.
GRAPHICAL_SESSION="$(loginctl --json=short 2>/dev/null | jq -r '[.[] | select(.seat != null and .seat != "-")] | first | .session' || true)"
if [ -n "$GRAPHICAL_SESSION" ] && [ "$GRAPHICAL_SESSION" != "null" ]; then
  loginctl unlock-session "$GRAPHICAL_SESSION"
fi

niri msg output DP-2 on
