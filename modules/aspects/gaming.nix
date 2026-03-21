{
  den,
  lib,
  ...
}:
{
  den.aspects.gaming = {
    includes = [ ];

    nixos =
      { pkgs, config, ... }:
      {
        options.modules.gaming = {
          enable = lib.mkEnableOption "gaming setup";
        };

        config = lib.mkIf config.modules.gaming.enable {
          services.sunshine = {
            enable = true;
            openFirewall = true;
            capSysAdmin = true;
            settings = {
              output_name = 2;
            };
            applications.apps = [
              {
                name = "Steam Big Picture";
                cmd = "";
                prep-cmd = [
                  {
                    do = "niri msg action focus-monitor DP-2";
                    undo = "niri msg action focus-monitor DP-1";
                  }
                  {
                    do = "";
                    undo = "setsid steam steam://close/bigpicture";
                  }
                ];
                detached = [ "setsid steam steam://open/bigpicture" ];
                auto-detach = "true";
              }
            ];
          };
          hardware.xpadneo.enable = true;
          programs = {
            steam = {
              enable = true;
              protontricks.enable = true;
              gamescopeSession = {
                enable = true;
                args = [
                  "-H"
                  "1080"
                  "-O"
                  "DP-1"
                  "--adaptive-sync"
                ];
              };
              remotePlay.openFirewall = true;
              localNetworkGameTransfers.openFirewall = true;
              extraCompatPackages = with pkgs; [
                proton-ge-bin
              ];
            };

            gamescope = {
              enable = true;
            };
            gamemode.enable = true;
          };
          environment.systemPackages = with pkgs; [
            (heroic.override {
              extraPkgs =
                pkgs': with pkgs'; [
                  gamescope
                  gamemode
                ];
            })
          ];
        };
      };
  };
}
