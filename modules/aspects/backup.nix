{
  den,
  lib,
  ...
}:
{
  den.aspects.backup = {
    # Auto-include the offsite restic provide: a host that asks for "backup"
    # wants its state covered. Splitting it into a separate `_.restic` was a
    # footgun — pi only included the base and silently lost its restic job.
    includes = [ den.aspects.backup._.restic ];
    nixos =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      {
        options.modules.backup = {
          paths = lib.mkOption {
            description = "Directories the offsite restic job covers on this host.";
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          repository = lib.mkOption {
            description = ''
              Restic repository for the offsite job. Null falls back to the
              union-backed per-host path.
            '';
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
        };

        config = {
          services.rsync = {
            enable = true;
            jobs = lib.optionalAttrs (config.networking.hostName == "alpha") {
              buptohdd = {
                destination = "/mnt/hdd/backup";
                sources = [
                  "${config.users.users.repparw.home}/Pictures"
                  "${config.users.users.repparw.home}/Documents"
                  "${config.users.users.repparw.home}/.config"
                ];
                settings = {
                  archive = true;
                  delete = true;
                };
              };
              buprpi = {
                destination = "${config.modules.services.backupDir}/pi-services/";
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

    provides.restic = {
      nixos =
        {
          config,
          pkgs,
          lib,
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

          # Weekly offsite-repo weight report: how much the crypt repo
          # occupies on the drive after prune, plus snapshot count. Posts to
          # #notifications via the bot token like the other monitors.
          systemd.services.restic-size-report = {
            description = "Report offsite restic repository size to Discord";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            path = [
              (lib.getExe pkgs.rclone)
              pkgs.restic
              pkgs.jq
              pkgs.curl
            ];
            environment = {
              RCLONE_CONFIG = config.sops.templates."rclone.conf".path;
              RESTIC_PASSWORD_FILE = config.sops.secrets.resticPassword.path;
            };
            serviceConfig = {
              Type = "oneshot";
              TimeoutStartSec = "30min";
            };
            script =
              let
                channelId = "1515064288191053979";
              in
              ''
                # shellcheck disable=SC1091
                source /run/secrets/hermes-env
                host=$(cat /etc/hostname)
                repo="rclone:gd-crypt:restic/$host"

                size_json=$(rclone size "$repo" --json)
                bytes=$(jq -r .bytes <<<"$size_json")
                objects=$(jq -r .count <<<"$size_json")
                gib=$(awk -v b="$bytes" 'BEGIN{printf "%.1f", b/1073741824}')

                snaps=$(RESTIC_REPOSITORY="$repo" ${lib.getExe pkgs.restic} snapshots --json | jq length)

                curl -s -m 15 -X POST \
                  -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
                  -H "Content-Type: application/json" \
                  -d "$(jq -n --arg c "*$host* offsite: ''${gib} GiB across $snaps snapshots ($objects objects)" '{content: $c}')" \
                  "https://discord.com/api/v10/channels/${channelId}/messages" >/dev/null || true
              '';
          };

          systemd.timers.restic-size-report = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "Mon *-*-* 07:00:00";
              Persistent = true;
              RandomizedDelaySec = "10min";
            };
          };
        };
    };
  };
}
