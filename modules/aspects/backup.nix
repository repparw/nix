{
  den,
  lib,
  ...
}:
{
  den.aspects.backup = {
    provides.restic = {
      nixos =
        {
          config,
          pkgs,
          ...
        }:
        let
          bcfg = config.modules.backup;
        in
        {
          sops.secrets = {
            resticPassword = {
              sopsFile = ../../secrets/backup.sops.yaml;
            };
            rcloneDriveId.sopsFile = ../../secrets/rclone.sops.yaml;
            rcloneDriveSecret.sopsFile = ../../secrets/rclone.sops.yaml;
            rcloneDriveToken.sopsFile = ../../secrets/rclone.sops.yaml;
            rcloneCrypt.sopsFile = ../../secrets/rclone.sops.yaml;
          };

          # System-level rclone config, rendered by sops at activation with
          # secret values substituted: rclone has no path indirection in
          # config values, so a static /etc conf referencing /run/secrets
          # paths is read literally and fails.
          sops.templates."rclone.conf" = {
            mode = "0400";
            content = ''
              [gdrive]
              type = drive
              scope = drive
              client_id = ${config.sops.placeholder.rcloneDriveId}
              client_secret = ${config.sops.placeholder.rcloneDriveSecret}
              token = ${config.sops.placeholder.rcloneDriveToken}

              [gd-crypt]
              type = crypt
              # Dedicated drive folder, OUTSIDE the gdrive:crypt leg the
              # user-level crypt union serves: backups never mix with
              # synced personal data.
              remote = gdrive:nixos-backups
              password = ${config.sops.placeholder.rcloneCrypt}
            '';
          };

          systemd.services.restic-backups-offsite = {
            environment.RCLONE_CONFIG = config.sops.templates."rclone.conf".path;
          };

          services.restic.backups.offsite = {
            repository =
              if bcfg.repository != null then
                bcfg.repository
              else
                "rclone:gd-crypt:restic/${config.networking.hostName}";
            passwordFile = config.sops.secrets.resticPassword.path;
            initialize = true;
            inhibitsSleep = true;
            paths = config.modules.backup.paths;
            exclude = [
              # Electron/browser cache and shader junk: the bulk of .config
              # with near-zero restore value.
              "**/cache/**"
              "**/Cache/**"
              "**/Code Cache/**"
              "**/GPUCache/**"
              "**/DawnGraphiteCache/**"
              "**/DawnWebGPUCache/**"
              "**/ShaderCache/**"
              "**/CachedData/**"
              "**/Crashpad/**"
              "**/Service Worker/**"
              "/home/repparw/.config/heroic/**"
              "/home/repparw/.config/clipse/**"
              # Owner-managed archive (still in Documents).
              "/home/repparw/Documents/Memorias/**"
            ];
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
              OnCalendar = "*-*-* 05:00:00";
              RandomizedDelaySec = "15min";
              Persistent = true;
            };
          };
        };
    };

    nixos =
      {
        config,
        pkgs,
        ...
      }:
      let
        cfg = config.modules.services;
        user = config.users.users.repparw;
        userHome = user.home;
      in
      {
        # Alpha-local rsync mirrors: HDD copy of personal dirs and the old
        # pi-services pull. Offsite restic lives in provides.restic.
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
