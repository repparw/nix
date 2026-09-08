{
  den,
  lib,
  ...
}:
{
  den.aspects.gaming = {
    provides.to-hosts.nixos =
      { pkgs, ... }:
      let
        # GE-Proton 11-6 is newer than the version in the pinned nixpkgs and is
        # the first release with Steam-overlay support for Wine-Wayland. Use
        # GitHub's release-asset digests directly so the pin remains auditable.
        protonGe11_6 =
          let
            version = "GE-Proton11-6";
            variant =
              if pkgs.stdenv.hostPlatform.isx86_64 then
                {
                  arch = "x86_64";
                  hash = "sha256-ZZ+NcfL3hlk0ASCyDBxaFGSqE4k5MyoTdt6iL20twuQ=";
                }
              else if pkgs.stdenv.hostPlatform.isAarch64 then
                {
                  arch = "aarch64";
                  hash = "sha256-d5KdzV+VGxobif5ZTZGHijrflRZAb2gHaXGYjuLP30M=";
                }
              else
                throw "GE-Proton 11-6 is only packaged for x86_64 and aarch64";
          in
          pkgs.stdenvNoCC.mkDerivation {
            pname = "proton-ge-bin";
            inherit version;

            src = pkgs.fetchurl {
              url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${version}/${version}-${variant.arch}.tar.gz";
              inherit (variant) hash;
            };

            dontUnpack = true;
            dontConfigure = true;
            dontBuild = true;
            outputs = [
              "out"
              "steamcompattool"
            ];
            nativeBuildInputs = [
              pkgs.gnutar
              pkgs.gzip
            ];

            installPhase = ''
              runHook preInstall

              echo "Use programs.steam.extraCompatPackages, not environment.systemPackages." > "$out"
              mkdir -p "$steamcompattool"
              tar -xzf "$src" --strip-components=1 -C "$steamcompattool"
              substituteInPlace "$steamcompattool/compatibilitytool.vdf" \
                --replace-fail "${version}-${variant.arch}" "GE-Proton"

              runHook postInstall
            '';

            meta = {
              homepage = "https://github.com/GloriousEggroll/proton-ge-custom";
              license = lib.licenses.bsd3;
              platforms = [
                "x86_64-linux"
                "aarch64-linux"
              ];
              sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            };
          };
      in
      {
        boot.kernelModules = [ "ntsync" ];
        hardware.xpadneo.enable = true;
        programs = {
          steam = {
            enable = true;
            extraCompatPackages = [ protonGe11_6 ];
            remotePlay.openFirewall = true;
            localNetworkGameTransfers.openFirewall = true;
          };

          gamemode.enable = true;
          gamescope.enable = true;
        };
        environment.systemPackages = with pkgs; [
          shipwright
          hydralauncher
          (heroic.override {
            extraPkgs =
              pkgs': with pkgs'; [
                gamescope
                gamemode
                mangohud
                protonGe11_6
              ];
          })
        ];

        services.udev.extraRules = ''
          # 8BitDo Ultimate 2C Wireless - remove kernel deadzone and fuzz for Hall effect sticks
          # https://web.archive.org/web/20260508175350/https://old.reddit.com/r/linux_gaming/comments/1t75mmu/why_your_tmrhall_effect_sticks_might_feel_off_on/okmje9v/
          ATTRS{idVendor}=="2dc8", ATTRS{idProduct}=="310a", RUN+="${pkgs.linuxConsoleTools}/bin/evdev-joystick --evdev /dev/input/%k --deadzone 0 --fuzz 0"
        '';
      };

    user = _: {
      extraGroups = [ "gamemode" ];
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
