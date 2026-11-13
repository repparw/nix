{
  den,
  ...
}:
{
  den.aspects.gaming = {
    user = _: {
      extraGroups = [ "gamemode" ];
    };

    provides.to-hosts.nixos =
      { pkgs, ... }:
      let
        gamingEnvironment = {
          PROTON_FSR4_UPGRADE = "1";
        };

        heroicSteam = pkgs.runCommand "heroic-steam" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
          mkdir -p $out/bin
          makeWrapper ${pkgs.heroic}/bin/heroic $out/bin/heroic \
            --run 'if [ "''${SteamClientLaunch:-}" = 1 ]; then export SDL_GAMECONTROLLER_IGNORE_DEVICES=0xdead/0xbeef; fi'
        '';
      in
      {
        nixpkgs.overlays = [
          (_final: prev: {
            heroic = prev.heroic.override {
              extraPkgs = pkgs': [ pkgs'.gamemode ];
              extraEnv = gamingEnvironment;
            };
          })
        ];

        boot.kernelModules = [ "ntsync" ];
        hardware.xpadneo.enable = true;
        programs = {
          steam = {
            enable = true;
            remotePlay.openFirewall = true;
            localNetworkGameTransfers.openFirewall = true;
            package = pkgs.steam.override {
              extraEnv = gamingEnvironment;
              extraBwrapArgs = [
                "--tmpfs /mnt"
                "--tmpfs /home/containers/media"
              ];
            };
            extraPackages = [
              heroicSteam
              pkgs.gamemode
            ];
          };

          gamemode.enable = true;
          gamescope = {
            enable = true;
            # Lets gamescope renice itself to -20 and ask for realtime priority
            # Vulkan queues. gamescope 3.17 retries with regular priority queues
            # when the driver refuses them (VK_ERROR_NOT_PERMITTED_KHR).
            capSysNice = true;
          };
        };
        environment.systemPackages = with pkgs; [
          heroic
        ];

        services.udev.extraRules = ''
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
