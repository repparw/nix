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
[drive]
type = drive
client_id = 333265659347-c03ga8iml374j79nod16pb79kkfkel7f.apps.googleusercontent.com
client_secret = 
scope = drive
token = {"access_token":"ya29.a0AZYkNZjtJOkBQ154MTCmKfABtzzzi2V0POU8d0xQgyBoebu07Dx9wedpvlQVhJFZJGGvkKJk6AEGDaa0J1P_d4TDHQ2ZjW5OZxb57-TG5q7qSfm4IVKuM6EaNN0lWO3kewUUXWJRl5fhe-lEshdGPy48vi2CWLfrhI4xHVldsVUaCgYKAYoSARISFQHGX2MiIpf6Nr9HpNsseHrVjvhVaA0178","token_type":"Bearer","refresh_token":"1//0h3Uq0IBe-va7CgYIARAAGBESNwF-L9IrGs4NA664UoJ-aiccvanLL-2Y0aCha-gzJKlBYZIE_KR5p2sW40jic7gCKZBMuRf_2qc","expiry":"2025-04-07T01:00:16.289771212-03:00"}
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
