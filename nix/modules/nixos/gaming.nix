{ ... }:
{
  hardware.xpadneo.enable = true;
  boot.extraModprobeConfig = ''
    	options bluetooth disable_ertm=1
  '';

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
