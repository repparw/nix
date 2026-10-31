{ den, lib, ... }:
{
  den.aspects.lan-edge.nixos =
    { config, pkgs, ... }:
    let
      servicesLib = import ../_services/lib.nix { inherit lib pkgs; };
      jellyfinHost = "Host(`${config.modules.services.definitions.jellyfin.hostname}.${config.modules.services.domain}`)";
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
              rule = jellyfinHost;
              service = "jellyfin";
              tls.certResolver = "cloudflare";
              middlewares = [ "hsts" ];
            };
            routers.jellyfin-login = {
              rule = "${jellyfinHost} && PathPrefix(`/Users/AuthenticateByName`)";
              service = "jellyfin";
              tls.certResolver = "cloudflare";
              middlewares = [
                "hsts"
                "jellyfin-login-limit"
              ];
            };
            middlewares.hsts.headers.stsSeconds = 2592000;
            middlewares.jellyfin-login-limit.rateLimit = {
              average = 5;
              burst = 10;
              period = "1m";
            };
            services.jellyfin.loadBalancer.servers = [
              { url = servicesLib.serviceUrl config.modules.services config "jellyfin"; }
            ];
          };
        };
      };
    };
}
