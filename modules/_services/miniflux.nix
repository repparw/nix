{
  cfg,
  config,
  lib,
  pkgs,
  ...
}:
let
  backupJob = import ./backup-job.nix { inherit lib pkgs; };
  backupDir = "${cfg.configDir}/miniflux";
  createBackup = pkgs.writeShellApplication {
    name = "miniflux-create-backup";
    runtimeInputs = [
      config.services.postgresql.package
      pkgs.coreutils
      pkgs.gzip
    ];
    text = ''
      set -euo pipefail
      path="${backupDir}/miniflux-backup-$(date --iso-8601=seconds).sql.gz"
      pg_dump --dbname='${config.services.miniflux.config.DATABASE_URL}' --format=plain --no-owner \
        | gzip -9 > "$path"
      echo "backup created: $path"
    '';
  };
in
{
  services.miniflux = {
    enable = true;
    config = {
      BASE_URL = "https://rss.${cfg.domain}";
      LISTEN_ADDR = "0.0.0.0:8081";
      CREATE_ADMIN = 0;
      RUN_MIGRATIONS = 1;
      CLEANUP_FREQUENCY_HOURS = 24;
    };
  };
}
// (backupJob {
  name = "miniflux";
  description = "miniflux PostgreSQL";
  inherit backupDir createBackup;
  filePattern = "miniflux-backup-*.sql.gz";
  owner = "miniflux";
  serviceConfig.User = "miniflux";
})
