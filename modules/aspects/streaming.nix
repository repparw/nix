{
  lib,
  config,
  pkgs,
  ...
}:
{
  den.aspects.streaming = {
    nixos =
      { pkgs, ... }:
      let
        niri-output-on = pkgs.writeShellScriptBin "niri-output-on" ''
          #!/usr/bin/env bash
          # Load Niri environment from user session
          export $(systemctl --user show-environment | grep '^NIRI_SOCKET=')
          ${lib.getExe pkgs.niri} msg output DP-2 on
          ${lib.getExe pkgs.niri} msg output DP-2 mode "2560x1440@119.986"
        '';
        niri-output-off = pkgs.writeShellScriptBin "niri-output-off" ''
          #!/usr/bin/env bash
          export $(systemctl --user show-environment | grep '^NIRI_SOCKET=')
          ${lib.getExe pkgs.niri} msg output DP-2 off
        '';
        steam-sunshine = pkgs.writeShellScriptBin "steam-sunshine" ''
          #!/usr/bin/env bash
          set -x
          exec >> /tmp/steam-sunshine.log 2>&1

          echo "=== Starting Steam in Gamescope on DP-2 at $(date) ==="

          # Kill any existing Steam or gamescope
          pgrep -x steam >/dev/null 2>&1 && pkill -9 -x steam
          pgrep -x gamescope >/dev/null 2>&1 && pkill -9 -x gamescope
          sleep 2

          # Start gamescope with Steam inside it on DP-2
          # Gamescope handles game window management internally
          ${lib.getExe pkgs.gamescope} \
            -W 2560 -H 1440 -r 120 \
            -e \
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
            WINDOW_ID=$(${lib.getExe pkgs.niri} msg --json windows | ${lib.getExe pkgs.jq} -r '.[] | select(.app_id == "gamescope" or (.title // "" | ascii_downcase | contains("gamescope"))) | .id' | head -1)

            if [ -n "$WINDOW_ID" ] && [ "$WINDOW_ID" != "null" ]; then
              echo "Found gamescope window $WINDOW_ID, moving to DP-2"
              ${lib.getExe pkgs.niri} msg action move-window-to-monitor DP-2 --id "$WINDOW_ID"
              sleep 0.5
              ${lib.getExe pkgs.niri} msg action focus-window --id "$WINDOW_ID"
              ${lib.getExe pkgs.niri} msg action raise-window --id "$WINDOW_ID"
              echo "Moved Gamescope to DP-2 and focused"

              # Power off all monitors via DPMS (doesn't affect output indices)
              sleep 0.5
              ${lib.getExe pkgs.niri} msg action power-off-monitors
              echo "Powered off monitors"

              break
            fi
          done

          # Wait for Steam to exit
          wait $STEAM_PID 2>/dev/null || true
          echo "Steam exited"
        '';
      in
      {
        services.sunshine = {
          enable = true;
          openFirewall = true;
          capSysAdmin = false; # Disabled per NixOS issue #463989

          settings = {
            output_name = 2;
            min_log_level = "info";
          };

          applications = {
            env = {
              PATH = "/run/current-system/sw/bin:/home/repparw/.local/bin";
            };
            apps = [
              {
                name = "Desktop";
                image-path = "desktop.png";
              }
              {
                name = "Steam Big Picture";
                cmd = "${steam-sunshine}/bin/steam-sunshine";
                image-path = "steam.png";
                prep-cmd = [
                  {
                    do = "${niri-output-on}/bin/niri-output-on";
                    undo = "${niri-output-off}/bin/niri-output-off";
                  }
                ];
              }
            ];
          };
        };
      };
  };
}
