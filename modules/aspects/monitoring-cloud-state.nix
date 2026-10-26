{ den, ... }:
{
  den.aspects.monitoring.provides.backup.nixos =
    { config, pkgs, ... }:
    let
      directory = "/var/lib/grafana-cloud-backup";
    in
    {
      sops.secrets.grafana-cloud-backup-token = {
        sopsFile = ../../secrets/grafana-cloud-epsilon.sops.yaml;
      };
      systemd.services.grafana-cloud-backup = {
        description = "Export private Grafana Cloud configuration for offsite backup";
        serviceConfig = {
          Type = "oneshot";
          LoadCredential = "token:${config.sops.secrets.grafana-cloud-backup-token.path}";
          StateDirectory = "grafana-cloud-backup";
          StateDirectoryMode = "0700";
          UMask = "0077";
          TimeoutStartSec = "10min";
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
        script = ''
          exec ${pkgs.python3}/bin/python3 ${../scripts/grafana-cloud-backup.py} \
            --url ${config.modules.monitoring.cloudUrl} \
            --token-file "$CREDENTIALS_DIRECTORY/token" \
            --output "$STATE_DIRECTORY"
        '';
      };
      environment.persistence."/persist".directories = [
        {
          inherit directory;
          mode = "0700";
        }
      ];
      modules.backup.exports.grafana-cloud-state = {
        unit = "grafana-cloud-backup.service";
        path = directory;
        pattern = "grafana-cloud-state.tar.gz";
      };
      modules.backup.paths = [ directory ];
    };
}
