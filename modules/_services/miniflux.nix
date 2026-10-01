{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.services;
  servicesLib = import ./lib.nix { inherit lib pkgs; };
  service = cfg.definitions.miniflux;
  stateDir = "${cfg.configDir}/miniflux";
  backupDir = "/srv/backups";
  createBackup = pkgs.writeShellApplication {
    name = "miniflux-create-backup";
    runtimeInputs = [
      pkgs.postgresql
      pkgs.coreutils
      pkgs.gzip
    ];
    text = ''
      set -euo pipefail
      path="${backupDir}/miniflux-backup-$(date --iso-8601=seconds).sql.gz"
      pg_dump --dbname='postgres:///miniflux' --format=plain --no-owner \
        | gzip -9 > "$path"
      echo "backup created: $path"
    '';
  };
in
{
  containers.miniflux = servicesLib.mkContainer {
    inherit cfg;
    name = "miniflux";
    extraOptions.timeoutStartSec = "10min";
    bindMounts = {
      "/var/lib/postgresql" = {
        hostPath = "${stateDir}/postgresql";
        isReadOnly = false;
      };
      "/srv/backups" = {
        hostPath = stateDir;
        isReadOnly = false;
      };
    };
    serviceConfig = {
      postgresql.enable = true;
      miniflux = {
        enable = true;
        config = {
          BASE_URL = "https://${service.hostname}.${cfg.domain}";
          LISTEN_ADDR = "0.0.0.0:${toString service.port}";
          CREATE_ADMIN = 0;
          RUN_MIGRATIONS = 1;
          CLEANUP_FREQUENCY_HOURS = 24;
          POLLING_PARSING_ERROR_LIMIT = 0;
        };
      };
    };
    extraConfig = {
      # The cluster was initdb'd on the host with en_IE.UTF-8; without that
      # locale inside the container every connection fails with "database
      # locale is incompatible" and postgresql-setup grinds until timeout.
      i18n.defaultLocale = "en_IE.UTF-8";
      i18n.extraLocaleSettings.LC_MONETARY = "es_AR.UTF-8";
      i18n.supportedLocales = [
        "C.UTF-8/UTF-8"
        "en_US.UTF-8/UTF-8"
        "en_IE.UTF-8/UTF-8"
        "es_AR.UTF-8/UTF-8"
      ];
      networking.firewall.allowedTCPPorts = [ service.port ];
    }
    // servicesLib.mkBackupJob {
      name = "miniflux";
      description = "miniflux PostgreSQL";
      inherit backupDir createBackup;
      filePattern = "miniflux-backup-*.sql.gz";
      owner = "miniflux";
      serviceConfig.User = "miniflux";
    };
  };
}
