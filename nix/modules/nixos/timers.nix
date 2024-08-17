{ pkgs, ... }:
{

  systemd.services.buptohdd = {
    serviceConfig = {
      Type = "oneshot";
      User = "repparw";
      ExecStart = "${pkgs.rsync}/bin/rsync -aq --delete /home/repparw/Pictures /home/repparw/Documents /home/repparw/.config --exclude='dlsuite' /mnt/hdd/backup";
    };
  };

  systemd.services.git-autocommit = {
    path = [ pkgs.git ];
    environment = {
      GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -i /home/repparw/.ssh/id_ed25519";
    };
    serviceConfig = {
      WorkingDirectory = "/home/repparw/.dotfiles";
      Type = "oneshot";
      User = "repparw";
      ExecStart = [ "git add -A; git diff-index --quiet --cached HEAD || git commit -m 'Autocommit'" ];
    };
  };

  systemd.services.rclone-sync = {
    path = [ pkgs.rclone ];
    serviceConfig = {
      Type = "oneshot";
      User = "repparw";
      ExecStart = "rclone -L sync --exclude \"authelia/valkey/\" --exclude \"authelia/config/notification.txt\" --exclude \"authelia/config/users_database.yml\" --exclude \"swag/keys/\" --exclude \"**/fail2ban/fail2ban.sqlite3\" --exclude \"**/letsencrypt/live/\" --exclude \"**/letsencrypt/archive/\" --exclude \"**/letsencrypt/accounts/\" /home/repparw/.config/dlsuite crypt:dlsuite";
    };
  };

  systemd.services.docker-cleanup = {
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "repparw";
      WorkingDirectory = "/tmp";
      ExecStart = "${pkgs.docker}/bin/docker system prune -af";
    };
  };

  systemd.timers.buptohdd = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:00:00";
      Persistent = true;
    };
  };

  systemd.timers.git-autocommit = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/4";
      Persistent = true;
    };
  };

  systemd.timers.rclone-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-7,14,21,28 00:00:00";
      Persistent = true;
    };
  };

  systemd.timers.docker-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-1,15 12:00:00";
      Persistent = true;
    };
  };

}
