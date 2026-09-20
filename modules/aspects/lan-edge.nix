{ den, lib, ... }:
{
  den.aspects.lan-edge.nixos =
    { config, pkgs, ... }:
    let
      servicesLib = import ../_services/lib.nix { inherit lib pkgs; };
    in
    {
      services.ddclient.enable = lib.mkForce false;

      networking.firewall = {
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
              rule = "Host(`jellyfin.${config.modules.services.domain}`)";
              service = "jellyfin";
              tls.certResolver = "cloudflare";
            };
            services.jellyfin.loadBalancer.servers = [
              { url = servicesLib.serviceUrl config.modules.services config "jellyfin"; }
            ];
          };
        };
      };
    };
}
