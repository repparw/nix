{ ... }:
{
  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      gamescopeSession.enable = true;
    };

    gamescope = {
      enable = true;
      capSysNice = true;
    };

    gamemode = {
      enable = true;
      enableRenice = true;
    };
  };
}
