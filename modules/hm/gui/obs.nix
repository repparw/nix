{
  pkgs,
  osConfig,
  ...
}: {
  config =
    if osConfig.programs.obs-studio.enable
    then {
      systemd.user.services."obs" = {
        Unit = {
          StartLimitIntervalSec = 60;
          StartLimitBurst = 4;
          After = ["graphical-session.target"];
        };

        Service = {
          ExecStart = [
            "${pkgs.obs-studio}/bin/obs --disable-shutdown-check --startreplaybuffer --minimize-to-tray"
          ];
          Restart = ["on-failure"];
          RestartSec = 1;
        };
      };

      home.packages = with pkgs; [
        obs-cmd
      ];
    }
    else {};
}
