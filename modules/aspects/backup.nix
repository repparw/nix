{ den, ... }:
{
  den.aspects.backup = {
    includes = [ den.aspects.backup._.restic ];
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        exports = config.modules.backup.exports;
        exportReport = "/var/lib/backup-exports/offsite.json";
        backup = config.services.restic.backups.offsite;
        resticCommand = lib.escapeShellArgs (
          [ (lib.getExe backup.package) ]
          ++ lib.concatMap (option: [
            "-o"
            option
          ]) backup.extraOptions
        );
        prepareExports = pkgs.writeShellApplication {
          name = "prepare-offsite-exports";
          runtimeInputs = [
            pkgs.python3
            pkgs.systemd
          ];
          text = ''
            exec python3 ${../scripts/prepare-backup-exports.py} ${pkgs.writeText "backup-exports.json" (builtins.toJSON exports)} ${exportReport}
          '';
        };
      in
      {
        options.modules.backup = {
          retentionArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "--keep-daily 7"
              "--keep-weekly 4"
              "--keep-monthly 12"
            ];
            description = "Restic forget arguments, applied only after a complete export and successful upload.";
          };
          exports = lib.mkOption {
            description = "Native export units refreshed and checked before the scheduled or manual offsite backup.";
            default = { };
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  unit = lib.mkOption { type = lib.types.str; };
                  machine = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Nspawn machine containing the export unit, or null for a host unit.";
                  };
                  path = lib.mkOption { type = lib.types.str; };
                  pattern = lib.mkOption { type = lib.types.str; };
                  maxAgeSeconds = lib.mkOption {
                    type = lib.types.ints.positive;
                    default = 3600;
                    description = "Maximum artifact age after a successful export; at least one artifact must also be new or refreshed.";
                  };
                };
              }
            );
          };
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
          excludes = lib.mkOption {
            description = "Host-specific paths or globs excluded from the offsite backup.";
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
        config.systemd.services.restic-backups-offsite.preStart = lib.mkIf (exports != { }) (
          lib.mkBefore "${lib.getExe prepareExports}\n"
        );
        config.systemd.services.restic-backups-offsite.postStart = lib.mkIf (exports != { }) ''
          ${lib.getExe pkgs.python3} ${../scripts/prepare-backup-exports.py} --check ${exportReport}
          ${lib.optionalString (config.modules.backup.retentionArgs != [ ]) ''
            ${resticCommand} unlock
            ${resticCommand} forget --prune ${lib.concatStringsSep " " config.modules.backup.retentionArgs}
          ''}
        '';
        config.systemd.services.restic-backups-offsite.serviceConfig = lib.mkIf (exports != { }) {
          StateDirectory = [ "backup-exports" ];
          StateDirectoryMode = "0700";
        };
        config.services.restic.backups.offsite.paths = lib.mkIf (exports != { }) (
          lib.mkAfter [ exportReport ]
        );
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
          repository =
            if bcfg.repository != null then
              bcfg.repository
            else
              "rclone:gd-crypt:restic/${config.networking.hostName}";
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
              remote = gdrive:nixos-backups
              password = ${config.sops.placeholder.rcloneCrypt}
            '';
          };

          systemd.services.restic-backups-offsite = {
            environment.RCLONE_CONFIG = config.sops.templates."rclone.conf".path;
          };

          services.restic.backups.offsite = {
            inherit repository;
            passwordFile = config.sops.secrets.resticPassword.path;
            initialize = true;
            inhibitsSleep = true;
            paths = bcfg.paths;
            exclude = [
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
            ]
            ++ bcfg.excludes;
            extraOptions = [
              "rclone.program=${lib.getExe pkgs.rclone}"
            ];
            pruneOpts = lib.optionals (bcfg.exports == { }) bcfg.retentionArgs;
            checkOpts = [ "--read-data-subset=5%" ];
            timerConfig = {
              OnCalendar = "*-*-* 01:00:00";
              RandomizedDelaySec = "15min";
              Persistent = true;
            };
          };

          systemd.services.restic-size-report = {
            description = "Report offsite restic repository size to Discord";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            path = [
              pkgs.rclone
              pkgs.restic
              pkgs.jq
              pkgs.curl
              pkgs.gawk
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
                channelId = config.modules.services.discordChannelId;
              in
              ''
                # shellcheck disable=SC1091
                source /run/secrets/hermes-env
                host=$(cat /etc/hostname)
                repo="rclone:gd-crypt:restic/$host"
                rclone_remote="gd-crypt:restic/$host"

                size_json=$(rclone size "$rclone_remote" --json)
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
