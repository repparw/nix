{
  lib,
  config,
  pkgs,
  ...
}:

# TODO: HDR over Sunshine is currently blocked by multiple missing pieces:
#   1. Niri doesn't support HDR output even with an HDR EDID.
#   2. capSysAdmin = false forces wlroots screencopy capture instead of KMS;
#      HDR on Linux generally needs KMS.
#   3. Dummy/virtual DRM driver lacks color-management props.
# The virtual display now uses an LG CX EDID with HDR10 + BT2020 metadata,
# so the kernel at least reports an HDR-capable connector.
# To enable HDR we would need: a compositor with HDR support (KWin or Gamescope),
# KMS capture, and HEVC/AV1 10-bit.
{
  den.aspects.streaming = {
    nixos =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
        virtualDisplay = config.modules.virtualDisplay or { };
        height = lib.last (lib.splitString "x" (virtualDisplay.resolution or "3840x2160"));
        refreshRate = toString (virtualDisplay.refreshRate or 120);

        niri-output-on = pkgs.writeShellScriptBin "niri-output-on" (builtins.readFile ./niri-output-on.sh);
        steam-sunshine = pkgs.writeShellApplication {
          name = "steam-sunshine";
          runtimeInputs = [
            pkgs.bubblewrap
            pkgs.jq
          ];
          text = ''
            export GAMESCOPE_HEIGHT=${height}
            export GAMESCOPE_REFRESH=${refreshRate}
          ''
          + builtins.readFile ./steam-sunshine.sh;
        };
        heroic-sunshine = pkgs.writeShellApplication {
          name = "heroic-sunshine";
          runtimeInputs = [ pkgs.jq ];
          text = ''
            export GAMESCOPE_HEIGHT=${height}
            export GAMESCOPE_REFRESH=${refreshRate}
          ''
          + builtins.readFile ./heroic-sunshine.sh;
        };
        steam-sunshine-cleanup = pkgs.writeShellApplication {
          name = "steam-sunshine-cleanup";
          text = ''
            eval "$(systemctl --user show-environment | grep '^NIRI_SOCKET=')"
            niri msg output DP-2 off
            pkill -9 gamescope || true
            pkill -9 steam || true
            pkill -9 heroic || true
            pkill -f "systemd-inhibit.*--who=Sunshine" 2>/dev/null || true
          '';
        };
      in
      {
        services.sunshine = {
          enable = true;
          openFirewall = true;
          capSysAdmin = false; # Disabled per https://github.com/NixOS/nixpkgs/issues/463989

          settings = {
            output_name = 2; # DP-2 where gamescope/Steam runs
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
                detached = [ "${steam-sunshine}/bin/steam-sunshine" ];
                image-path = "steam.png";
                prep-cmd = [
                  {
                    do = "${niri-output-on}/bin/niri-output-on";
                    undo = "${steam-sunshine-cleanup}/bin/steam-sunshine-cleanup";
                  }
                ];
              }
              {
                name = "Heroic Games Launcher";
                detached = [ "${heroic-sunshine}/bin/heroic-sunshine" ];
                image-path = "heroic.png";
                prep-cmd = [
                  {
                    do = "${niri-output-on}/bin/niri-output-on";
                    undo = "${steam-sunshine-cleanup}/bin/steam-sunshine-cleanup";
                  }
                ];
              }
            ];
          };
        };
      };
  };
}
