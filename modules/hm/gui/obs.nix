{
  pkgs,
  osConfig,
  ...
}:
{
  config =
    if osConfig.programs.obs-studio.enable then
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
      }
    else
      { };
}
