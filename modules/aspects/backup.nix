{
  lib,
  ...
}:
{
  den.aspects.backup = {
    nixos =
      {
        config,
        pkgs,
        ...
      }:
      let
        cfg = config.modules.services;
      in
      {
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
              };
            };
            buptocrypt = {
              destination = "/home/repparw/.cloud/crypt/bup";
              sources = [
                "/home/repparw/Pictures"
                "/home/repparw/Documents"
              ];
              settings = {
                archive = true;
                delete = true;
              };
            };
            buprpi = {
              destination = "${cfg.backupDir}/pi-services/";
              sources = [ "pi:services/" ];
              settings = {
                archive = true;
                delete = true;
              };
            };
          };
        };

        systemd = {
          services.rclone-sync-crypt = {
            serviceConfig = {
              Type = "oneshot";
              User = "repparw";
              ExecStart = ''
                ${lib.getExe pkgs.rclone} -L sync --exclude-from ${cfg.backupDir}/.rclone-exclude ${cfg.backupDir} crypt:dlsuite
              '';
            };
          };

          timers.rclone-sync-crypt = {
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
