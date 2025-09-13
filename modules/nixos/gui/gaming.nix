{
  lib,
  config,
  ...
}:
let
  cfg = config.modules.gaming;
in
{
  options.modules.gaming = {
    enable = lib.mkEnableOption "gaming setup";
  };

  config = lib.mkIf (cfg.enable && config.modules.gui.enable) {
    # hardware.xpadneo.enable = true;

    programs = {
      steam = {
        enable = true;
        gamescopeSession = {
          enable = true;
          args = [
            "--backend"
            "sdl"
            "--adaptive-sync"

            # output resolution
            "-W"
            "1920"
            "-H"
            "1080"

            # game resolution
            # "-w"
            # "1920"
            # "-h"
            # "1080"

            # upscaling
            # "-F"
            # "fsr"
          ];
        };
        remotePlay.openFirewall = true;
        localNetworkGameTransfers.openFirewall = true;
      };

      gamescope = {
        enable = true;
        capSysNice = true;
      };
    };
  };
}
