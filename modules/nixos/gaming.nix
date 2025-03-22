{
  config,
  lib,
  ...
}: let
  cfg = config.modules.gaming;
in {
  options.modules.gaming = {
    enable = lib.mkEnableOption "gaming setup";
  };

  config = lib.mkIf cfg.enable {
    hardware.xpadneo.enable = false;

    programs = {
      steam = {
        enable = true;
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
