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
        boot.kernelModules = [ "ntsync" ];
        hardware.xpadneo.enable = true;
        programs = {
          steam = {
            enable = true;
            extraCompatPackages = with pkgs; [ proton-ge-bin ];
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
    homeManager =
      { config, pkgs, ... }:
      let
        sm64Baserom = "${config.home.homeDirectory}/Games/sm64/rom.z64";
      in
      {
        home.packages = with pkgs; [ shadps4 ];
        programs.sm64ex = lib.mkIf (builtins.pathExists sm64Baserom) {
          enable = true;
          region = "us";
          baserom = sm64Baserom;
        };
        programs.mangohud = {
          enable = true;
          settings = {
            preset = 2;
          };
        };
      };
  };
}
