{
  pkgs,
  lib,
  osConfig,
  ...
}:
{
  config = lib.mkIf osConfig.programs.obs-studio.enable {
    systemd.user.services."obs" = {
      Unit = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 4;
        After = [ "graphical-session.target" ];
      };

      Service = {
        ExecStart = [
          "${lib.getExe pkgs.obs-studio} --disable-shutdown-check --startreplaybuffer --minimize-to-tray"
        ];
        Restart = [ "on-failure" ];
        RestartSec = 1;
      };
    };

    home.packages = with pkgs; [
      obs-cmd
    ];
  };
}
