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
            extraCompatPackages = with pkgs; [ proton-ge-bin ];
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
          shipwright
          (heroic.override {
            extraPkgs =
              pkgs': with pkgs'; [
                gamescope
                gamemode
                mangohud
                proton-ge-bin
              ];
          })
        ];

        services.udev.extraRules = ''
          # 8BitDo Ultimate 2C Wireless - remove kernel deadzone and fuzz for Hall effect sticks
          # https://web.archive.org/web/20260508175350/https://old.reddit.com/r/linux_gaming/comments/1t75mmu/why_your_tmrhall_effect_sticks_might_feel_off_on/okmje9v/
          ATTRS{idVendor}=="2dc8", ATTRS{idProduct}=="310a", RUN+="${pkgs.linuxConsoleTools}/bin/evdev-joystick --evdev /dev/input/%k --deadzone 0 --fuzz 0"
        '';
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
