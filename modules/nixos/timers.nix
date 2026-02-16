{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.modules.timers;
in
{
  options.modules.timers = {
    enable = lib.mkEnableOption "Timer services";
  };

  config = lib.mkIf cfg.enable {
    services.rsync = {
      enable = true;
      jobs = {
        buptohdd = {
          destination = "/mnt/hdd/backup";
          sources = [
            "/home/repparw/Pictures"
            "/home/repparw/Documents"
            "/home/repparw/.config"
          ];
          settings = {
            archive = true;
            delete = true;
            exclude = "dlsuite";
          };
        };
        buprpi = {
          destination = "/home/repparw/.config/dlsuite/pi-services/";
          sources = [ "pi:services/" ];
          settings = {
            archive = true;
            delete = true;
          };
        };
      };
    };

    systemd = {
      services = {
        rclone-sync-crypt = {
          serviceConfig = {
            Type = "oneshot";
            User = "repparw";
            ExecStart = ''
              ${lib.getExe pkgs.rclone} -L sync --exclude-from /home/repparw/.config/dlsuite/exclude-file.txt /home/repparw/.config/dlsuite crypt:dlsuite
            '';
          };
        };

        paperless-export = {
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe pkgs.podman} exec paperless document_exporter ../export";
          };
        };
      };

      timers = {
        paperless-export = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-7,14,21,28 03:45:00";
            Persistent = true;
          };
        };

        rclone-sync-crypt = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-7,14,21,28 04:00:00";
            Persistent = true;
          };
        };
      };
    };
  };
}
