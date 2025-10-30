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
    systemd = {
      services = {
        buptohdd = {
          serviceConfig = {
            Type = "oneshot";
            User = "repparw";
            ExecStart = "${lib.getExe pkgs.rsync} -aq --delete /home/repparw/Pictures /home/repparw/Documents /home/repparw/.config --exclude='dlsuite' /mnt/hdd/backup";
          };
        };
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
        buptohdd = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "03:00:00";
            Persistent = true;
          };
        };

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
