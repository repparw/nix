{ boot, config, ... }:
{
  hardware.xpadneo.enable = true;

  boot = {
    extraModulePackages = with config.boot.kernelPackages; [ xpadneo ];
    extraModProbeConfig = ''
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

}
