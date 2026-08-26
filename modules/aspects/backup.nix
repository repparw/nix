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

          # System-level rclone config, rendered at unit start from sops
          # secret contents: rclone has no path indirection for config
          # values, so a static /etc file referencing secret paths is read
          # literally (observed 2026-08-25: base64 decode fail at byte 0,
          # i.e. rclone treating "/nix/store/..." as the password).
          # Prepended before the module's own ExecStartPre so the repo-init
          # step already sees the finished conf.
          systemd.services.restic-backups-offsite = {
            environment.RCLONE_CONFIG = "/run/restic-backups-offsite/rclone.conf";
            serviceConfig = {
              UMask = lib.mkForce "0077";
              ExecStartPre = lib.mkBefore [
                (lib.getExe (
                  pkgs.writeShellApplication {
                    name = "render-rclone-conf";
                    text = ''
                      conf=/run/restic-backups-offsite/rclone.conf
                      {
                        echo "[gdrive]"
                        echo "type = drive"
                        echo "scope = drive"
                        echo "client_id = $(cat ${config.sops.secrets.rcloneDriveId.path})"
                        echo "client_secret = $(cat ${config.sops.secrets.rcloneDriveSecret.path})"
                        echo "token = $(cat ${config.sops.secrets.rcloneDriveToken.path})"
                        echo ""
                        echo "[gd-crypt]"
                        echo "type = crypt"
                        echo "remote = gdrive:crypt"
                        echo "password = $(cat ${config.sops.secrets.rcloneCrypt.path})"
                      } > "$conf"
                      chmod 600 "$conf"
                    '';
                  }
                ))
              ];
            };
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
