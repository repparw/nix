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
        lib,
        ...
      }:
      let
        cfg = config.modules.services;
        user = config.users.users.repparw;
        userHome = user.home;
      in
      {
        sops.secrets.resticPassword = {
          sopsFile = ../../secrets/backup.sops.yaml;
          owner = user.name;
        };

        services.restic = {
          backups.crypt = {
            repository = "rclone:crypt:restic/alpha";
            passwordFile = config.sops.secrets.resticPassword.path;
            initialize = true;
            inhibitsSleep = true;
            paths = [
              cfg.backupDir
              "${userHome}/Pictures"
              "${userHome}/Documents"
              "${userHome}/.config"
            ];
            exclude = [
              "${cfg.backupDir}/.rclone-exclude"
            ];
            rcloneConfigFile = "${userHome}/.config/rclone/rclone.conf";
            extraOptions = [
              "rclone.program=${lib.getExe pkgs.rclone}"
            ];
            pruneOpts = [
              "--keep-daily 7"
              "--keep-weekly 4"
              "--keep-monthly 12"
            ];
            checkOpts = [ "--read-data-subset=5%" ];
            timerConfig = {
              OnCalendar = "*-*-7,14,21,28 04:00:00";
              Persistent = true;
            };
          };
        };

        services.rsync = {
          enable = true;
          jobs = {
            buptohdd = {
              destination = "/mnt/hdd/backup";
              sources = [
                "${userHome}/Pictures"
                "${userHome}/Documents"
                "${userHome}/.config"
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
                "copy-links" = true;
                delete = true;
              };
            };
          };
        };

      };
  };
}
