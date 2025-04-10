{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.modules.timers;
in {
  options.modules.timers = {
    enable = lib.mkEnableOption "Timer services";
  };

  config = lib.mkIf cfg.enable {
    age.secrets = {
      rcloneDrive = {
        file = ../../secrets/rclone-drive.age;
      };
      rcloneCrypt = {
        file = ../../secrets/rclone-crypt.age;
      };
      rcloneDropbox = {
        file = ../../secrets/rclone-dropbox.age;
      };
    };

    systemd = {
      services = {
        buptohdd = {
          serviceConfig = {
            Type = "oneshot";
            User = "repparw";
            ExecStart = "${lib.getExe pkgs.rsync} -aq --delete /home/repparw/Pictures /home/repparw/Documents /home/repparw/.config --exclude='dlsuite' /mnt/hdd/backup";
          };
        };
        rclone-sync = {
          serviceConfig = {
            Type = "oneshot";
            User = "repparw";
            ExecStart = "${lib.getExe pkgs.rclone} -L sync --exclude \"authelia/valkey/\" --exclude \"authelia/config/notification.txt\" --exclude \"authelia/config/users_database.yml\" --exclude \"swag/keys/\" --exclude \"**/fail2ban/fail2ban.sqlite3\" --exclude \"**/letsencrypt/live/\" --exclude \"**/letsencrypt/archive/\" --exclude \"**/letsencrypt/accounts/\" --exclude \"swag/nginx/**/*.sample\" /home/repparw/.config/dlsuite crypt:dlsuite";
          };
        };

        docker-cleanup = {
          requires = ["docker.service"];
          wantedBy = ["multi-user.target"];
          after = ["docker.service"];
          serviceConfig = {
            Type = "oneshot";
            User = "repparw";
            WorkingDirectory = "/tmp";
            ExecStart = "${lib.getExe pkgs.docker} system prune -af";
          };
        };
      };

      timers = {
        buptohdd = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "03:00:00";
            Persistent = true;
          };
        };

        rclone-sync = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "*-*-7,14,21,28 00:00:00";
            Persistent = true;
          };
        };

        docker-cleanup = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "*-*-1,15 12:00:00";
            Persistent = true;
          };
        };
      };
    };
  };
}
