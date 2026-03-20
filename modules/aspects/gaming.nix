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
          hardware.xpadneo.enable = true;
          programs = {
            steam = {
              enable = true;
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
