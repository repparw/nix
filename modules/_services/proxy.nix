{
  cfg,
  config,
  lib,
  ...
}:
let
  domain = cfg.domain;
  dynamicConfig = {
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
        freshrss = {
          rule = "Host(`rss.${domain}`)";
          service = "freshrss";
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
        qbit-basic-auth.headers.customRequestHeaders.Authorization =
          config.sops.placeholder.qbittorrentAuth;
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
        freshrss.loadBalancer.servers = [
          { url = "http://${config.containers.freshrss.localAddress}:8082"; }
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
in
{
  sops.templates."traefik-dynamic.json" = {
    path = "/var/lib/traefik/dynamic.json";
    owner = "traefik";
    content = builtins.toJSON dynamicConfig;
  };

  services.traefik = {
    enable = true;
    environmentFiles = [
      config.sops.secrets.cloudflare.path
    ];
    dynamicConfigFile = config.sops.templates."traefik-dynamic.json".path;
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
          forwardedHeaders.trustedIPs = [
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
            "2c0f:f248::/32"
          ];
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
        storage = "/var/lib/traefik/certs/acme.json";
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
            { url = "http://${config.containers.miniflux.localAddress}:8080"; }
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

  systemd.tmpfiles.rules = [
    "d /var/lib/traefik/certs 0755 traefik traefik -"
  ];
}
