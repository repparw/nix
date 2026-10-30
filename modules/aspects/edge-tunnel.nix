{ lib, ... }:
{
  den.aspects.edge-tunnel.nixos =
    { config, ... }:
    let
      cfg = config.modules.services;
      names = [
        cfg.domain
      ]
      ++ lib.mapAttrsToList (_: service: "${service.hostname}.${cfg.domain}") (
        lib.filterAttrs (name: service: service.hostname != null && name != "jellyfin") cfg.definitions
      )
      ++ [
        "grafana.${cfg.domain}"
        "metrics.${cfg.domain}"
      ];
    in
    {
      services.ddclient.enable = lib.mkForce false;

      sops.secrets.cloudflareTunnelCredentials = {
        sopsFile = ../../secrets/proxy.sops.yaml;
        restartUnits = [ "cloudflared-tunnel-epsilon-edge.service" ];
      };

      services.cloudflared = {
        enable = true;
        tunnels.epsilon-edge = {
          credentialsFile = config.sops.secrets.cloudflareTunnelCredentials.path;
          default = "http_status:404";
          ingress = builtins.listToAttrs (
            map (hostname: {
              name = hostname;
              value = {
                service = "https://127.0.0.1:8443";
                originRequest.originServerName = hostname;
              };
            }) names
          );
        };
      };

      services.traefik.staticConfigOptions.entryPoints.tunnel = {
        address = "127.0.0.1:8443";
        asDefault = true;
        forwardedHeaders.trustedIPs = [ "127.0.0.1/32" ];
        http.tls.certResolver = "cloudflare";
      };
      systemd.services.cloudflared-tunnel-epsilon-edge.after = [ "traefik.service" ];
    };
}
