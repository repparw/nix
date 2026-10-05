{ den, ... }:
{
  den.aspects.backup = {
    includes = [ den.aspects.backup._.restic ];
    nixos =
      { lib, ... }:
      {
        options.modules.backup = {
          hostRecovery.enable = lib.mkEnableOption "host identity, account, home and container recovery backups";
          hostRecovery.package = lib.mkOption {
            type = lib.types.package;
            readOnly = true;
            description = "Full filesystem checkpoint and isolated restore verification command.";
          };
          hostRecovery.quiesceUnits = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Running application units stopped only for an explicit full --quiesce checkpoint.";
          };
          hostRecovery.capturePaths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Application paths archived while quiesceUnits are stopped, before an offsite transfer.";
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
          fullPaths = lib.attrNames (
            lib.filterAttrs (
              _: fs:
              lib.elem fs.fsType [
                "ext4"
                "vfat"
                "btrfs"
                "xfs"
              ]
            ) config.fileSystems
          );
          fullExcludes = [
            "/proc"
            "/sys"
            "/dev"
            "/run"
            "/tmp"
            "/var/tmp"
            "/var/cache/restic-backups-offsite"
          ]
          ++ map (swap: swap.device) config.swapDevices
          ++ map (path: "/var/lib/nixos-containers/*/${path}") [
            "nix"
            "proc"
            "sys"
            "dev"
            "run"
            "tmp"
          ];
          recoveryPackage = pkgs.writeShellApplication {
            name = "host-recovery";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.util-linux
              pkgs.systemd
              pkgs.restic
              pkgs.rclone
              pkgs.jq
              pkgs.sops
              pkgs.ssh-to-age
              pkgs.sqlite
              pkgs.gnutar
            ];
            text = ''
              export RESTIC_REPOSITORY="''${RESTIC_REPOSITORY:-${repository}}"
              export RESTIC_PASSWORD_FILE="''${RESTIC_PASSWORD_FILE:-${config.sops.secrets.resticPassword.path}}"
              export RCLONE_CONFIG="''${RCLONE_CONFIG:-${config.sops.templates."rclone.conf".path}}"
              export RESTIC_CACHE_DIR="''${RESTIC_CACHE_DIR:-/var/cache/restic-backups-offsite}"
              export RECOVERY_PATHS_FILE=${pkgs.writeText "recovery-filesystems" (lib.concatLines fullPaths)}
              export RECOVERY_EXCLUDES_FILE=${pkgs.writeText "recovery-excludes" (lib.concatLines fullExcludes)}
              export RECOVERY_UNITS_FILE=${pkgs.writeText "recovery-quiesce-units" (lib.concatLines bcfg.hostRecovery.quiesceUnits)}
              export RECOVERY_CAPTURE_PATHS_FILE=${pkgs.writeText "recovery-capture-paths" (lib.concatLines bcfg.hostRecovery.capturePaths)}
              export RECOVERY_BOOTSTRAP_FILE=${config.sops.secrets.repparwPasswordHash.sopsFile}
              ${builtins.readFile ../scripts/host-recovery.sh}
            '';
          };
        in
        {
          environment.systemPackages = lib.optional bcfg.hostRecovery.enable recoveryPackage;
          modules.backup = lib.mkIf bcfg.hostRecovery.enable {
            hostRecovery.package = recoveryPackage;
            paths = [
              "/etc"
              "/boot"
              "/root"
              "/home/repparw"
              "/var/lib/nixos"
              "/var/lib/nixos-containers"
              "/var/lib/systemd/timers"
              "/var/lib/host-recovery"
            ]
            # --one-file-system stops at nested boot mounts. Include firmware
            # and EFI filesystems explicitly as well as /boot on the root disk.
            ++ lib.filter (path: lib.hasPrefix "/boot/" path) fullPaths
            ++ lib.optional config.services.traefik.enable "/var/lib/traefik";
            excludes = [
              "**/.cache/**"
              "**/node_modules/**"
              "**/.direnv/**"
              "**/__pycache__/**"
              "/home/repparw/.swapfile"
              "/home/repparw/.local/share/Trash/**"
            ]
            ++ map (path: "/var/lib/nixos-containers/*/${path}") [
              "nix"
              "proc"
              "sys"
              "dev"
              "run"
              "tmp"
            ];
          };

          systemd.tmpfiles.rules = lib.mkIf bcfg.hostRecovery.enable [
            "d /var/lib/host-recovery 0700 root root -"
          ];

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
            extraBackupArgs = lib.optionals bcfg.hostRecovery.enable [ "--one-file-system" ];
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
