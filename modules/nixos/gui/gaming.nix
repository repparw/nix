{
  pkgs,
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
    hardware.xpadneo.enable = true;
    programs = {
      steam = {
        enable = true;
        gamescopeSession = {
          enable = true;
          args = [
            # output resolution, assumes 16:9 if no width
            "-H"
            "1080"

            # only works embedded, not nested
            "--adaptive-sync"
          ];
          # steamArgs = [
          #   "-gamepadui"
          #   "-steamos3"
          #   "-steampal"
          #   "-steamdeck"
          #   "-pipewire-dmabuf"
          # ];
        };
        remotePlay.openFirewall = true;
        localNetworkGameTransfers.openFirewall = true;
        extraCompatPackages = with pkgs; [
          proton-ge-bin
        ];
      };

      gamescope = {
        enable = true;
        capSysNice = true;
      };
    };
  };
}
