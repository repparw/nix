{
  den,
  lib,
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
        # One Heroic build for the desktop launcher and the Steam sandbox:
        # the sandbox copy is what non-Steam shortcuts actually execute.
        heroicWithMangohud = pkgs.heroic.override {
          extraPkgs =
            pkgs': with pkgs'; [
              mangohud
              gamemode
            ];
        };

        # Steam launches every Heroic shortcut with
        # SDL_GAMECONTROLLER_IGNORE_DEVICES set to every pad it knows about,
        # including the physical one. Its virtual pad never reaches a
        # Heroic-spawned Proton game, so the game ends up with no controller
        # at all (2026-10-18). Neutralize the inherited list for
        # Steam-launched runs only; a Heroic started from the desktop keeps
        # its environment untouched.
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
            # Hide the media library and the spinning-rust mounts from
            # Steam's startup mount scan (it stats every mount and Proton
            # maps them as DOS drives, waking idle disks). Games and prefixes
            # that live under /mnt run through the Heroic GUI instead, whose
            # launches are native and see the real mounts.
            # /run/media is deliberately not masked: bwrap cannot create that
            # mountpoint under root-owned /run, and the directory only exists
            # when udiskie happened to mount removable media since boot, which
            # killed steam at launch (2026-10-14). Removable sticks are flash;
            # harmless for Steam to see.
            package = pkgs.steam.override {
              extraBwrapArgs = [
                "--tmpfs /mnt"
                "--tmpfs /home/containers/media"
              ];
            };
            # Heroic's non-Steam shortcuts (nixpkgs PR #569601) resolve
            # `heroic` by bare name, and Heroic refuses to launch anything
            # with useGameMode unless `gamemoderun` is on $PATH. Steam's
            # launch runtime does not carry the system profile, so both must
            # exist inside the FHS sandbox; extraPackages is the module knob
            # that merges packages into it. Without them every non-Steam
            # entry dies silently before exec (2026-10-14: Control Resonant,
            # SM64, and Sekiro were all silent no-ops from Big Picture).
            extraPackages = [
              heroicSteam
              pkgs.gamemode
            ];
          };

          gamemode.enable = true;
          gamescope.enable = true;
        };
        environment.systemPackages = with pkgs; [
          shipwright
          heroicWithMangohud
        ];

        services.udev.extraRules = ''
          # The Deck-8 macropad's system keys are misclassified as a joystick;
          # Wine exposes it ahead of the gamepad and Sekiro ignores controller input.
          SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Churrosoft Deck-8 System Control", ENV{ID_INPUT_JOYSTICK}=""

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
        home.file.".local/share/Steam/compatibilitytools.d/GE-Proton".source =
          pkgs.proton-ge-bin.steamcompattool;
        home.file.".local/bin/bbport" = {
          executable = true;
          text = ''
            #!/usr/bin/env bash
            set -euo pipefail
            cd ${lib.escapeShellArg "${config.home.homeDirectory}/.local/share/bbport-test"}
            case "''${1:-play}" in
              play) exec nix-shell --impure shell-local.nix --run 'exec python3 launcher/bbport_launcher.py --play' ;;
              launcher) exec nix-shell --impure shell-local.nix --run 'exec python3 launcher/bbport_launcher.py' ;;
              build) exec nix-shell --impure shell-local.nix --run 'exec bash build.sh --test' ;;
              *) echo 'Usage: bbport [play|launcher|build]' >&2; exit 1 ;;
            esac
          '';
        };
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
