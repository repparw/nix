{ den, ... }:
{
  den.aspects.nixos-services.provides.grafana-alert-triage.nixos =
    { config, lib, pkgs, ... }:
    let
      cfg = config.modules.grafana-alert-triage;
      alertTriage = import ./hermes-alert/_package.nix { inherit pkgs; };
      directory = "/var/lib/grafana-alert-triage";
      # systemd-nspawn's private-users shift: Hermes uid/gid 345 on the
      # container maps to 327680 + 345 on the Epsilon host.
      hermesHostUid = "328025";
    in
    {
      options.modules.grafana-alert-triage = {
        enable = lib.mkEnableOption "Grafana Cloud webhook intake for Hermes incident triage";
        tokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Runtime path of the private bearer credential configured in Grafana Cloud.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.tokenFile != null;
            message = "Grafana alert triage requires a dedicated tokenFile; never embed a token in a URL or Nix store.";
          }
        ];

        systemd.tmpfiles.rules = [ "d ${directory} 0700 ${hermesHostUid} ${hermesHostUid} - -" ];
        environment.persistence."/persist".directories = [
          { directory = directory; mode = "0700"; }
        ];

        systemd.services.grafana-alert-triage = {
          description = "Authenticated Grafana Cloud alert intake for Hermes";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            Type = "simple";
            User = hermesHostUid;
            Group = hermesHostUid;
            StateDirectory = "grafana-alert-triage";
            StateDirectoryMode = "0700";
            LoadCredential = "token:${toString cfg.tokenFile}";
            ExecStart = "${lib.getExe alertTriage.receiver} serve --state ${directory} --token-file %d/token";
            Restart = "on-failure";
            RestartSec = "10s";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            UMask = "0077";
          };
        };

        # Reuse the existing Cloudflare Tunnel's apex hostname: no new public
        # DNS record or port. Traefik routes this exact path to loopback only.
        services.traefik.dynamicConfigOptions.http.routers.grafana-alert-triage = {
          rule = "Host(`${config.modules.services.domain}`) && Path(`/hooks/grafana`)";
          priority = 1000;
          entryPoints = [ "tunnel" ];
          service = "grafana-alert-triage";
          tls = { };
        };
        services.traefik.dynamicConfigOptions.http.services.grafana-alert-triage.loadBalancer.servers = [
          { url = "http://127.0.0.1:3988"; }
        ];
      };
    };
}
