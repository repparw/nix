{ config, lib, ... }:
let
  cfg = config.modules.gaming;
in
{
  options.modules.gaming = {
    enable = lib.mkEnableOption "gaming setup";
  };

  config = lib.mkIf cfg.enable {
    hardware.xpadneo.enable = true;

    boot = {
      extraModulePackages = with config.boot.kernelPackages; [ xpadneo ];
      extraModprobeConfig = ''
        	  options bluetooth disable_ertm=Y
        	'';
    };

    programs = {
      steam = {
        enable = true;
        remotePlay.openFirewall = true;
        gamescopeSession.enable = true;
        localNetworkGameTransfers.openFirewall = true;
      };

      gamescope = {
        enable = true;
        capSysNice = true;
      };
    };
  };
}
