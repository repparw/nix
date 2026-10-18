{
  den,
  ...
}:
{
  den.aspects.gaming = {
    user = _: {
      extraGroups = [ "gamemode" ];
    };

    nixos =
      { pkgs, ... }:
      let
        # Steam shortcuts resolve Heroic inside Steam's FHS environment.
        heroicWithMangohud = pkgs.heroic.override {
          extraPkgs =
            pkgs': with pkgs'; [
              mangohud
              gamemode
            ];
        };

        # Steam-launched Heroic games need the virtual controller; desktop
        # Heroic launches keep their inherited environment unchanged.
        heroicSteam = pkgs.runCommand "heroic-steam" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
          mkdir -p $out/bin
          makeWrapper ${heroicWithMangohud}/bin/heroic $out/bin/heroic \
            --run 'if [ "''${SteamClientLaunch:-}" = 1 ]; then export SDL_GAMECONTROLLER_IGNORE_DEVICES=0xdead/0xbeef; fi'
        '';
      in
      {
        boot.kernelModules = [ "ntsync" ];
        hardware.xpadneo.enable = true;
        programs = {
          steam = {
            enable = true;
            remotePlay.openFirewall = true;
            localNetworkGameTransfers.openFirewall = true;
            # Avoid Steam's mount scan waking idle disks. Keep /run/media
            # visible: masking it can fail when the mountpoint exists.
            package = pkgs.steam.override {
              extraBwrapArgs = [
                "--tmpfs /mnt"
                "--tmpfs /home/containers/media"
              ];
            };
            # Non-Steam Heroic shortcuts resolve `heroic` by name and need
            # `gamemoderun` on PATH, so provide both inside Steam's FHS.
            extraPackages = [
              heroicSteam
              pkgs.gamemode
            ];
          };

          gamemode.enable = true;
          gamescope.enable = true;
        };
        environment.systemPackages = with pkgs; [
          heroicWithMangohud
        ];

        services.udev.extraRules = ''
          # Keep Deck-8 system keys out of joystick discovery.
          SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Churrosoft Deck-8 System Control", ENV{ID_INPUT_JOYSTICK}=""

          # Remove the kernel deadzone and fuzz from 8BitDo Hall effect sticks.
          # https://web.archive.org/web/20260508175350/https://old.reddit.com/r/linux_gaming/comments/1t75mmu/why_your_tmrhall_effect_sticks_might_feel_off_on/okmje9v/
          ATTRS{idVendor}=="2dc8", ATTRS{idProduct}=="310a", RUN+="${pkgs.linuxConsoleTools}/bin/evdev-joystick --evdev /dev/input/%k --deadzone 0 --fuzz 0"
        '';
      };
    homeManager =
      { pkgs, ... }:
      {
        home.file.".local/share/Steam/compatibilitytools.d/GE-Proton".source =
          pkgs.proton-ge-bin.steamcompattool;
        programs.mangohud = {
          enable = true;
          settings = {
            preset = 2;
          };
        };
      };
  };
}
