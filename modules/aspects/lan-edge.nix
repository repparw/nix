{ den, ... }:
{
  # Minimal local edge for LAN HTTPS: Jellyfin reaches Alpha directly rather
  # than making local clients round-trip through the public Epsilon edge.
  den.aspects.lan-edge.nixos =
    { config, lib, ... }:
    {
      # Dynamic DNS has no consumer after the public edge moved to Epsilon;
      # the home address used by WireGuard and Jellyfin is static.
      services.ddclient.enable = lib.mkForce false;

      networking.firewall = {
        # Containers use public names pinned back to this edge, so server-side
        # OIDC traffic must be allowed from their bridge.
        extraInputRules = ''
          iifname "ve-*" tcp dport { 80, 443 } accept comment "containers -> local edge"
        '';
        interfaces.eth0.allowedTCPPorts = [
          80
          443
        ];
      };

      sops.secrets.cloudflare.sopsFile = ../../secrets/proxy.sops.yaml;

      services.traefik = {
        enable = true;
        environmentFiles = [ config.sops.secrets.cloudflare.path ];
        staticConfigOptions = {
          entryPoints.websecure = {
            address = ":443";
            http.tls.certResolver = "cloudflare";
          };
          certificatesResolvers.cloudflare.acme = {
            email = "ubritos@gmail.com";
            storage = "/var/lib/traefik/acme.json";
            dnsChallenge = {
              provider = "cloudflare";
              resolvers = [
                "1.1.1.1:53"
                "1.0.0.1:53"
              ];
            };
          };
        };
        dynamicConfigOptions = {
          tls.options.default.sniStrict = true;
          http = {
            routers.jellyfin = {
              rule = "Host(`jellyfin.repparw.com`)";
              service = "jellyfin";
              tls.certResolver = "cloudflare";
            };
            services.jellyfin.loadBalancer.servers = [ { url = "http://192.168.0.18:8096"; } ];
          };
        };
      };
    };
}
