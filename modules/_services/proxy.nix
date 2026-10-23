{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.services;
  domain = cfg.domain;
  servicesLib = import ./lib.nix { inherit lib pkgs; };
  serviceUrl = servicesLib.serviceUrl cfg config;
  ingressPolicy = import ./ingress-policy.nix { inherit lib; } {
    definitions = cfg.definitions;
    inherit domain;
    inherit serviceUrl;
  };
in
{
  sops.secrets = {
    cloudflare = {
      sopsFile = ../../secrets/proxy.sops.yaml;
      owner = config.users.users.repparw.name;
    };
    qbittorrentAuth = {
      sopsFile = ../../secrets/proxy.sops.yaml;
      owner = "traefik";
      group = "traefik";
      mode = "0400";
    };
  };

  services.traefik = {
    enable = true;
    environmentFiles = [
      config.sops.secrets.cloudflare.path
      config.sops.secrets.qbittorrentAuth.path
    ];
    staticConfigOptions = {
      entryPoints = {
        websecure = {
          address = ":443";
          asDefault = true;
          http = {
            tls.certResolver = "cloudflare";
          };
        };
      };

      ping = { };
      api = {
        dashboard = true;
        debug = true;
      };
      certificatesResolvers.cloudflare.acme = {
        email = "ubritos@gmail.com";
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
        inherit (ingressPolicy.traefik) routers middlewares services;
      };
    };
  };

}
