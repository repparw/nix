{
  den,
  lib,
  ...
}:
{
  den.aspects.gaming = {
    includes = [ ];

    nixos =
      { pkgs, ... }:
      {
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
          };

          gamemode.enable = true;
          gamescope.enable = true;
        };
        environment.systemPackages = with pkgs; [
          (heroic.override {
            extraPkgs =
              pkgs': with pkgs'; [
                gamescope
                gamemode
                mangohud
              ];
          })
        ];
      };
    homeManager = _: {
      programs.mangohud = {
        enable = true;
        settings = {
          preset = 2;
        };
      };
    };
  };
}
