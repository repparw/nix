{
  config,
  pkgs,
  lib,
  ...
}:
{
  options.programs.rquickshare.enable = lib.mkEnableOption "rquickshare";

  config = lib.mkIf config.programs.rquickshare.enable {
    home.packages = [ pkgs.rquickshare ];

    xdg.dataFile."dev.mandre.rquickshare/.settings.json" = {
      enable = true;
      text = ''
        {
          "realclose": false,
          "autostart": true,
          "startminimized": true,
          "download_path": "${config.xdg.userDirs.download}",
          "port": 32100
        }
      '';
      force = true;
    };

    systemd.user.services.rquickshare = {
      Unit = {
        Description = "RQuickShare - Quick Share for Linux";
        After = [ "graphical-session.target" ];
        Wants = [ "graphical-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${pkgs.rquickshare}/bin/rquickshare";
        Restart = "on-failure";
        RestartSec = 5;
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
