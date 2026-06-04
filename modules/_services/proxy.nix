{
  cfg,
  config,
  lib,
  ...
}:
let
  domain = cfg.domain;
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
        routers = {
          home-router = {
            rule = "Host(`home.${domain}`)";
            service = "hass";
            middlewares = [ "real-ip" ];
          };
          oc-router = {
            rule = "Host(`opencode.${domain}`)";
            service = "opencode";
            middlewares = [ "authelia" ];
          };
          authelia = {
            rule = "Host(`auth.${domain}`)";
            service = "authelia";
          };
          bazarr = {
            rule = "Host(`bazarr.${domain}`)";
            service = "bazarr";
            middlewares = [ "authelia" ];
          };
          prowlarr = {
            rule = "Host(`prowlarr.${domain}`)";
            service = "prowlarr";
            middlewares = [ "authelia" ];
          };
          radarr = {
            rule = "Host(`radarr.${domain}`)";
            service = "radarr";
            middlewares = [ "authelia" ];
          };
          sonarr = {
            rule = "Host(`sonarr.${domain}`)";
            service = "sonarr";
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
          changedetection = {
            rule = "Host(`changedetection.${domain}`)";
            service = "changedetection";
            middlewares = [ "authelia" ];
          };
          miniflux = {
            rule = "Host(`rss.${domain}`)";
            service = "miniflux";
            middlewares = [ "authelia" ];
          };
          jellyfin = {
            rule = "Host(`jellyfin.${domain}`)";
            service = "jellyfin";
          };
          ntfy = {
            rule = "Host(`ntfy.${domain}`)";
            service = "ntfy";
            middlewares = [ "authelia" ];
          };
          paperless = {
            rule = "Host(`paper.${domain}`)";
            service = "paperless";
            middlewares = [ "authelia" ];
          };
          glance = {
            rule = "Host(`${domain}`)";
            service = "glance";
          };

        };
        middlewares = {
          real-ip.plugin.traefik-real-ip = { };
          authelia.forwardAuth = {
            address = "http://${config.containers.authelia.localAddress}:9091/api/authz/forward-auth";
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
          qbit-basic-auth.headers.customRequestHeaders.Authorization = "\${QBIT_AUTH}";
        };
        services = {
          hass.loadBalancer.servers = [ { url = "http://192.168.0.4"; } ];
          opencode.loadBalancer.servers = [ { url = "http://localhost:4096"; } ];
          authelia.loadBalancer.servers = [
            { url = "http://${config.containers.authelia.localAddress}:9091"; }
          ];
          bazarr.loadBalancer.servers = [ { url = "http://${config.containers.bazarr.localAddress}:6767"; } ];
          prowlarr.loadBalancer.servers = [
            { url = "http://${config.containers.prowlarr.localAddress}:9696"; }
          ];
          radarr.loadBalancer.servers = [ { url = "http://${config.containers.radarr.localAddress}:7878"; } ];
          sonarr.loadBalancer.servers = [ { url = "http://${config.containers.sonarr.localAddress}:8989"; } ];
          qbittorrent.loadBalancer.servers = [
            { url = "http://${config.containers.qbittorrent.localAddress}:8080"; }
          ];
          changedetection.loadBalancer.servers = [
            { url = "http://${config.containers.changedetection.localAddress}:5000"; }
          ];
          miniflux.loadBalancer.servers = [
            { url = "http://127.0.0.1:8081"; }
          ];
          jellyfin.loadBalancer.servers = [
            { url = "http://${config.containers.jellyfin.localAddress}:8096"; }
          ];
          ntfy.loadBalancer.servers = [ { url = "http://${config.containers.ntfy.localAddress}:8090"; } ];
          paperless.loadBalancer.servers = [
            { url = "http://${config.containers.paperless.localAddress}:8000"; }
          ];
          glance.loadBalancer.servers = [ { url = "http://${config.containers.glance.localAddress}:8080"; } ];

        };
      };
    };
  };

}
