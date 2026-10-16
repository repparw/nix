{ den, ... }:
{
  den.aspects.backup = {
    includes = [ den.aspects.backup._.restic ];
    nixos =
      { lib, ... }:
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
          excludes = lib.mkOption {
            description = "Host-specific paths or globs excluded from the offsite backup.";
            type = lib.types.listOf lib.types.str;
            default = [ ];
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
            pruneOpts = [
              "--keep-daily 7"
              "--keep-weekly 4"
              "--keep-monthly 12"
            ];
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
                discordNotify =
                  (import ../_services/lib.nix { inherit lib pkgs; }).mkDiscordNotify pkgs
                    config.modules.services.discordChannelId;
              in
              ''
                host=$(cat /etc/hostname)
                repo="rclone:gd-crypt:restic/$host"
                rclone_remote="gd-crypt:restic/$host"

                size_json=$(rclone size "$rclone_remote" --json)
                bytes=$(jq -r .bytes <<<"$size_json")
                objects=$(jq -r .count <<<"$size_json")
                gib=$(awk -v b="$bytes" 'BEGIN{printf "%.1f", b/1073741824}')

                snaps=$(RESTIC_REPOSITORY="$repo" ${lib.getExe pkgs.restic} snapshots --json | jq length)

                ${lib.getExe discordNotify} post \
                  "*$host* offsite: ''${gib} GiB across $snaps snapshots ($objects objects)" >/dev/null || true
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
