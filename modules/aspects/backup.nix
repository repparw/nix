{
  den,
  inputs ? null,
  lib ? null,
  ...
}:
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
        mkResticCommand =
          options:
          lib.escapeShellArgs (
            lib.optionals backup.inhibitsSleep [
              "${pkgs.systemd}/bin/systemd-inhibit"
              "--mode=block"
              "--who=restic"
              "--what=sleep"
              "--why=Scheduled backup offsite"
            ]
            ++ [ (lib.getExe backup.package) ]
            ++ lib.concatMap (option: [
              "-o"
              option
            ]) options
          );
        resticCommand = mkResticCommand backup.extraOptions;
        # extraBackupArgs apply only to backup, but prune also uploads
        # repacked data. Keep Pi's macb TX-queue watchdog upload throttle.
        pruneUploadArgs = lib.filter (lib.hasPrefix "--limit-upload=") backup.extraBackupArgs;
        # Pruning needs at least two backend connections. Do not reduce
        # already valid limits on other hosts.
        pruneCommand =
          mkResticCommand (
            map (
              option: if option == "rclone.connections=1" then "rclone.connections=2" else option
            ) backup.extraOptions
          )
          + lib.optionalString (pruneUploadArgs != [ ]) " ${lib.escapeShellArgs pruneUploadArgs}";
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
            description = "Native exports prepared or checked for freshness before the scheduled or manual offsite backup.";
            default = { };
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  unit = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Export unit to run, or null to check artifacts produced by the app scheduler.";
                  };
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
                    description = "Maximum artifact age. When unit is set, at least one artifact must also be new or refreshed.";
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
          homeState = lib.mkOption {
            description = ''
              Home-relative paths staged by the home-state backup for the HDD
              mirror and the offsite staging tree. Curated small irreplaceable
              state; everything else is nix-declared, OAuth/session
              (re-login), or regenerable cache.
            '';
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          homeStateExcludes = lib.mkOption {
            description = "Rsync exclude patterns applied below the homeState --relative anchor.";
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          homeStateCritical = lib.mkOption {
            description = ''
              Subset of homeState guarded as critical: when a source exists it
              must be unlocked by its owning tool, staged non-empty, and
              parseable, or the export fails and the previous staged
              generation is preserved. A missing source is tolerated until the
              first successful backup has recorded it under
              stateRoot/.critical-seen; afterwards a missing source fails the
              export so a deleted critical file is flagged by fleet health
              instead of silently dropping out of coverage.
            '';
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          homeStateStagingScript = lib.mkOption {
            description = ''
              The prepare-home-state script staging homeState, as set by the
              host that defines the staging units. Exposed for manual runs
              and recovery verification.
            '';
            type = lib.types.nullOr lib.types.package;
            default = null;
          };
        };
        # Clear stale locks (interrupted manual runs) before the module's
        # post-start check demands an exclusive lock; the forget unlock runs
        # too late to help there (observed 2026-10-18 on pi).
        config.systemd.services.restic-backups-offsite.preStart = lib.mkMerge [
          (lib.mkIf (exports != { }) (lib.mkBefore "${lib.getExe prepareExports}\n"))
          (lib.mkAfter "${resticCommand} unlock\n")
        ];
        config.systemd.services.restic-backups-offsite.postStart = lib.mkIf (exports != { }) ''
          ${lib.getExe pkgs.python3} ${../scripts/prepare-backup-exports.py} --check ${exportReport}
          ${lib.optionalString (config.modules.backup.retentionArgs != [ ]) ''
            ${resticCommand} unlock
            ${pruneCommand} forget --prune ${lib.concatStringsSep " " config.modules.backup.retentionArgs}
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
          backup = config.services.restic.backups.offsite;
          claroRepo = "rclone:claro:restic-replica/${config.networking.hostName}";
          rcloneConnections = lib.findFirst (lib.hasPrefix "rclone.connections=") "" backup.extraOptions;
          uploadLimit = lib.findFirst (lib.hasPrefix "--limit-upload=") "" backup.extraBackupArgs;
          replicaProgram = pkgs.writeShellApplication {
            name = "restic-claro-replica";
            runtimeInputs = [
              pkgs.restic
              pkgs.rclone
              pkgs.jq
            ];
            text = builtins.readFile ../scripts/restic-claro-replica.sh;
          };
          replicaEnvironment = {
            RCLONE_CONFIG = config.sops.templates."rclone.conf".path;
            RCLONE_BIN = lib.getExe pkgs.rclone;
            RESTIC_REPOSITORY = claroRepo;
            RESTIC_FROM_REPOSITORY = repository;
            RESTIC_PASSWORD_FILE = config.sops.secrets.resticPassword.path;
            RESTIC_RETENTION_ARGS = lib.concatStringsSep " " bcfg.retentionArgs;
            RESTIC_RCLONE_CONNECTIONS = lib.removePrefix "rclone.connections=" rcloneConnections;
            RESTIC_UPLOAD_LIMIT_KIB = lib.removePrefix "--limit-upload=" uploadLimit;
          };
          replicaUnit = command: {
            description = "Restic Claro Drive replica (${command})";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            environment = replicaEnvironment;
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${lib.getExe replicaProgram} ${command}";
              TimeoutStartSec = "36h";
            };
          };
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
            rcloneClarodrive.sopsFile = ../../secrets/rclone.sops.yaml;
            rcloneClarodriveUser.sopsFile = ../../secrets/rclone.sops.yaml;
            rcloneClarodriveUrl.sopsFile = ../../secrets/rclone.sops.yaml;
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

              [claro]
              type = webdav
              vendor = nextcloud
              url = ${config.sops.placeholder.rcloneClarodriveUrl}
              user = ${config.sops.placeholder.rcloneClarodriveUser}
              pass = ${config.sops.placeholder.rcloneClarodrive}
            '';
          };

          systemd.services.restic-backups-offsite = {
            environment.RCLONE_CONFIG = config.sops.templates."rclone.conf".path;
          };

          # Secondary failure evidence must not change primary backup status.
          modules.fleet-unit-state.retainedJobs = [ "restic-claro-replica" ];

          systemd.services.restic-claro-replica-preflight = replicaUnit "preflight";
          systemd.services.restic-claro-replica = replicaUnit "copy";
          systemd.timers.restic-claro-replica = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              # Stagger the three hosts against the shared 75 GB account and
              # avoid simultaneous first copies over the limited upload link.
              OnCalendar =
                if config.networking.hostName == "alpha" then
                  "Sat *-*-* 05:00:00"
                else if config.networking.hostName == "pi" then
                  "Tue *-*-* 05:00:00"
                else
                  "Thu *-*-* 05:00:00";
              RandomizedDelaySec = "1h";
              Persistent = true;
            };
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
            extraOptions = [ "rclone.program=${lib.getExe pkgs.rclone}" ];
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
  perSystem = { pkgs, ... }: {
    checks.claro-replica = pkgs.runCommand "check-claro-replica" {
      nativeBuildInputs = [
        pkgs.python3
        pkgs.bash
        pkgs.shellcheck
      ];
    } ''
      shellcheck -s bash ${../scripts/restic-claro-replica.sh}
      python3 ${../_tests/restic-claro-replica.py} ${../scripts/restic-claro-replica.sh}
      touch "$out"
    '';

    checks.backup-exports =
      let
        piPostStart = builtins.unsafeDiscardStringContext (
          inputs.self.nixosConfigurations.pi.config.systemd.services.restic-backups-offsite.postStart
        );
        lines = lib.splitString "\n" piPostStart;
        pruneLine = lib.findFirst (lib.hasInfix "forget --prune") "" lines;
        unlockLine = lib.findFirst (lib.hasInfix " unlock") "" lines;
      in
      assert lib.hasInfix "rclone.connections=2" pruneLine;
      assert lib.hasInfix "--limit-upload=2048" pruneLine;
      assert lib.hasInfix "rclone.connections=1" unlockLine;
      pkgs.runCommand "backup-exports" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        PYTHONDONTWRITEBYTECODE=1 python3 ${../_tests/backup-exports.py} ${../scripts/prepare-backup-exports.py}
        touch "$out"
      '';
  };

}
