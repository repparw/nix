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
          ${pkgs.niri}/bin/niri msg output DP-2 on
          ${pkgs.niri}/bin/niri msg output DP-2 mode 2560x1440@119.986
        '';
        niri-output-off = pkgs.writeShellScriptBin "niri-output-off" ''
          #!/usr/bin/env bash
          export $(systemctl --user show-environment | grep '^NIRI_SOCKET=')
          ${pkgs.niri}/bin/niri msg output DP-2 off
        '';
        steam-sunshine = pkgs.writeShellScriptBin "steam-sunshine" ''
          #!/usr/bin/env bash
          set -x
          exec >> /tmp/steam-sunshine.log 2>&1

          echo "=== Starting Steam on DP-2 at $(date) ==="

          # Kill any existing Steam (exact match to avoid killing this script)
          pgrep -x steam >/dev/null 2>&1 && pkill -9 -x steam
          sleep 2

          # WORKAROUND: Force Steam to use XWayland to avoid 25-min lag bug
          # See: https://github.com/ValveSoftware/steam-for-linux/issues/11446
          export SDL_VIDEODRIVER=x11

          steam -tenfoot -pipewire-dmabuf &
          STEAM_PID=$!
          echo "Steam PID: $STEAM_PID"

          # Wait for window and move to DP-2
          for i in {1..30}; do
            sleep 0.5

            # Check if Steam died
            if ! kill -0 $STEAM_PID 2>/dev/null; then
              echo "Steam process not found, checking for window anyway"
              break
            fi

            # Find Steam window - check both app_id and title for XWayland
            WINDOW_ID=$(${pkgs.niri}/bin/niri msg --json windows | ${pkgs.jq}/bin/jq -r '.[] | select((.app_id // "" | ascii_downcase | contains("steam")) or (.title // "" | ascii_downcase | contains("steam"))) | .id' | head -1)

            if [ -n "$WINDOW_ID" ] && [ "$WINDOW_ID" != "null" ]; then
              echo "Found window $WINDOW_ID, moving to DP-2"
              ${pkgs.niri}/bin/niri msg action focus-window --id "$WINDOW_ID"
              sleep 0.5
              ${pkgs.niri}/bin/niri msg action move-window-to-monitor DP-2
              sleep 0.5
              # Toggle fullscreen to fix resolution after moving to 1440p
              ${pkgs.niri}/bin/niri msg action fullscreen-window --id "$WINDOW_ID"
              echo "Moved Steam to DP-2 and toggled fullscreen"
              break
            fi
          done

          # Kill screenshare popup if it appears (xdg-desktop-portal dialog)
          # Poll for up to 5 seconds since it can take a while to appear
          for i in {1..10}; do
            sleep 0.5
            SCREENSHARE_ID=$(${pkgs.niri}/bin/niri msg --json windows | ${pkgs.jq}/bin/jq -r '.[] | select(.app_id == "xdg-desktop-portal-gnome") | .id' | head -1)
            if [ -n "$SCREENSHARE_ID" ] && [ "$SCREENSHARE_ID" != "null" ]; then
              echo "Closing screenshare popup $SCREENSHARE_ID"
              ${pkgs.niri}/bin/niri msg action close-window --id "$SCREENSHARE_ID"
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

        # Install helper scripts for Steam Big Picture
        environment.systemPackages = [
          niri-output-on
          niri-output-off
          steam-sunshine
        ];
      };
  };
}
