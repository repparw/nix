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
    systemd.services = {
      buptohdd = {
        serviceConfig = {
          Type = "oneshot";
          User = "repparw";
          ExecStart = "${lib.getExe pkgs.rsync} -aq --delete /home/repparw/Pictures /home/repparw/Documents /home/repparw/.config --exclude='dlsuite' /mnt/hdd/backup";
        };
      };
    };

    systemd.services.rclone-sync = {
      serviceConfig = {
        Type = "oneshot";
        User = "repparw";
        ExecStart = "${lib.getExe pkgs.rclone} -L sync --exclude \"authelia/valkey/\" --exclude \"authelia/config/notification.txt\" --exclude \"authelia/config/users_database.yml\" --exclude \"swag/keys/\" --exclude \"**/fail2ban/fail2ban.sqlite3\" --exclude \"**/letsencrypt/live/\" --exclude \"**/letsencrypt/archive/\" --exclude \"**/letsencrypt/accounts/\" --exclude \"swag/nginx/**/*.sample\" /home/repparw/.config/dlsuite crypt:dlsuite";
      };
    };

    systemd.services.docker-cleanup = {
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

    systemd.timers.buptohdd = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "03:00:00";
        Persistent = true;
      };
    };

    systemd.timers.rclone-sync = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-7,14,21,28 00:00:00";
        Persistent = true;
      };
    };

    systemd.timers.docker-cleanup = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-1,15 12:00:00";
        Persistent = true;
      };
    };
  };
}
