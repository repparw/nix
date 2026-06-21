{
  cfg,
  config,
  lib,
  servicesLib,
  ...
}:
let
  domain = cfg.domain;
  inventory = cfg.inventory;
  proxyableInventory = lib.filterAttrs (_: service: service.port != null) inventory;
  routableInventory = lib.filterAttrs (
    name: service:
    service.hostname != null
    && !(builtins.elem name [
      "qbittorrent"
    ])
  ) inventory;
  mkService = name: {
    loadBalancer.servers = [ { url = servicesLib.serviceUrl cfg name; } ];
  };
  mkRouter =
    name: service:
    {
      rule = "Host(`${service.hostname}.${domain}`)";
      service = name;
    }
    // lib.optionalAttrs (service.auth == "one_factor") {
      middlewares = [ "authelia" ];
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
        routers = lib.mapAttrs mkRouter routableInventory // {
          home-router = {
            rule = "Host(`home.${domain}`)";
            service = "hass";
          };
          t3code = {
            rule = "Host(`code.${domain}`)";
            service = "t3code";
            middlewares = [ "authelia" ];
          };
          qbittorrent = {
            rule = "Host(`qbit.${domain}`) && !PathPrefix(`/api`)";
            service = "qbittorrent";
            middlewares = [ "qbit-auth" ];
          };
          qbittorrent-api = {
            rule = "Host(`qbit.${domain}`) && PathPrefix(`/api`)";
            service = "qbittorrent";
          };
          glance = {
            rule = "Host(`${domain}`)";
            service = "glance";
          };

        };
        middlewares = {
          authelia.forwardAuth = {
            address = "${servicesLib.serviceUrl cfg "authelia"}/api/authz/forward-auth";
            trustForwardHeader = true;
            authResponseHeaders = [
              "Remote-User"
              "Remote-Groups"
              "Remote-Email"
              "Remote-Name"
            ];
          };
          qbit-auth.chain.middlewares = [
            "authelia"
            "qbit-basic-auth"
          ];
          qbit-basic-auth.headers.customRequestHeaders.Authorization = "{{ env `QBIT_AUTH` }}";
        };
        services = lib.mapAttrs (name: _: mkService name) proxyableInventory // {
          hass.loadBalancer = {
            servers = [ { url = "http://192.168.0.4"; } ];
            healthCheck = {
              path = "/";
              interval = "10s";
              timeout = "3s";
            };
          };
          t3code.loadBalancer.servers = [ { url = "http://localhost:4097"; } ];
        };
      };
    };
  };

}
