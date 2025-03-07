{ pkgs, ... }:
{
  systemd.user.services."obs" = {
    Unit = {
      StartLimitIntervalSec = 60;
      StartLimitBurst = 4;
    };

    Service = {
      ExecStart = [
        "${pkgs.obs-studio}/bin/obs --disable-shutdown-check --startreplaybuffer --minimize-to-tray"
      ];
      Restart = [ "on-failure" ];
      RestartSec = 1;
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  home.packages = with pkgs; [
    obs-cmd
  ];

  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;
    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-pipewire-audio-capture
      obs-backgroundremoval
    ];
  };

}
