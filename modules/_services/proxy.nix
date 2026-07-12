{
  cfg,
  config,
  lib,
  servicesLib,
  ...
}:
let
  domain = cfg.domain;
  ingressPolicy = import ./ingress-policy.nix { inherit lib; } {
    definitions = cfg.definitions;
    inherit domain;
    serviceUrl = servicesLib.serviceUrl cfg;
  };
  # Cloudflare proxy IP ranges — https://www.cloudflare.com/ips-v4 / ips-v6
  cfIpRanges = [
    "173.245.48.0/20"
    "103.21.244.0/22"
    "103.22.200.0/22"
    "103.31.4.0/22"
    "141.101.64.0/18"
    "108.162.192.0/18"
    "190.93.240.0/20"
    "188.114.96.0/20"
    "197.234.240.0/22"
    "198.41.128.0/17"
    "162.158.0.0/15"
    "104.16.0.0/13"
    "104.24.0.0/14"
    "172.64.0.0/13"
    "131.0.72.0/22"
    "2400:cb00::/32"
    "2606:4700::/32"
    "2803:f800::/32"
    "2405:b500::/32"
    "2405:8100::/32"
    "2a06:98c0::/29"
    "2c0f:f250::/32"
  ];
in
{
  sops.secrets = {
    cloudflare = {
      sopsFile = ../../secrets/proxy.yaml;
      owner = config.users.users.repparw.name;
    };
    qbittorrentAuth = {
      sopsFile = ../../secrets/proxy.yaml;
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
        web = {
          address = ":80";
          http.redirections.entryPoint = {
            to = "websecure";
            scheme = "https";
          };
        };
        websecure = {
          address = ":443";
          asDefault = true;
          forwardedHeaders.trustedIPs = cfIpRanges;
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
