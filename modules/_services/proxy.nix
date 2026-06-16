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
          http.tls.certResolver = "cloudflare";
        };
      };
      experimental.plugins.traefik-real-ip = {
        moduleName = "github.com/zekihan/traefik-real-ip";
        version = "v0.1.20";
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
            middlewares = [ "real-ip" ];
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
          real-ip.plugin.traefik-real-ip = { };
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
