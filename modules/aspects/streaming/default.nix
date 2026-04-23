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
        niri-output-on = pkgs.writeShellScriptBin "niri-output-on" (builtins.readFile ./niri-output-on.sh);
        niri-output-off = pkgs.writeShellScriptBin "niri-output-off" (
          builtins.readFile ./niri-output-off.sh
        );
        steam-sunshine = pkgs.writeShellScriptBin "steam-sunshine" (builtins.readFile ./steam-sunshine.sh);
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
