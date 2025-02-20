{ ... }:
{
  hardware.xpadneo.enable = true;
  hardware.xone.enable = true;
  hardware.uinput.enable = true;

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
