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
    programs.rclone = {
      enable = true;
      remotes = {
drive = { config = {

secrets = { };
type = drive
client_id = 333265659347-c03ga8iml374j79nod16pb79kkfkel7f.apps.googleusercontent.com
client_secret = config.age.
scope = drive
team_drive = 

[crypt]
type = crypt
remote = drive:crypt
password = 

[dropbox]
type = dropbox


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
}
