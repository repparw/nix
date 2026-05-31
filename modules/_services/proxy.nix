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
    environmentFiles = [ config.sops.secrets.cloudflare.path ];
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
      experimental.localPlugins.cf-real-ip = {
        moduleName = "github.com/repparw/cf-real-ip";
        version = "v1.0.0";
      };
      ping = { };
      api = {
        dashboard = true;
        debug = true;
      };
      certificatesResolvers.cloudflare.acme = {
        email = "ubritos@gmail.com";
        storage = "${cfg.configDir}/traefik/certs/acme.json";
        dnsChallenge.provider = "cloudflare";
      };
    };
    dynamicConfigOptions = {
      tls.options.default.sniStrict = true;
      http = {
        routers = {
          home-router = {
            rule = "Host(`home.${domain}`)";
            service = "hass";
            entryPoints = [ "websecure" ];
            middlewares = [ "cf-real-ip" ];
            tls.certResolver = "cloudflare";
          };
          oc-router = {
            rule = "Host(`opencode.${domain}`)";
            service = "opencode";
            entryPoints = [ "websecure" ];
            middlewares = [ "authelia" ];
            tls.certResolver = "cloudflare";
          };
          authelia = {
            rule = "Host(`auth.${domain}`)";
            service = "authelia";
            tls = true;
          };
          bazarr = {
            rule = "Host(`bazarr.${domain}`)";
            service = "bazarr";
            middlewares = [ "authelia" ];
            tls = true;
          };
          prowlarr = {
            rule = "Host(`prowlarr.${domain}`)";
            service = "prowlarr";
            middlewares = [ "authelia" ];
            tls = true;
          };
          radarr = {
            rule = "Host(`radarr.${domain}`)";
            service = "radarr";
            middlewares = [ "authelia" ];
            tls = true;
          };
          sonarr = {
            rule = "Host(`sonarr.${domain}`)";
            service = "sonarr";
            middlewares = [ "authelia" ];
            tls = true;
          };
          qbittorrent = {
            rule = "Host(`qbit.${domain}`) && !PathPrefix(`/api`)";
            service = "qbittorrent";
            middlewares = [ "qbit-auth" ];
            tls = true;
          };
          qbittorrent-api = {
            rule = "Host(`qbit.${domain}`) && PathPrefix(`/api`)";
            service = "qbittorrent";
            tls = true;
          };
          changedetection = {
            rule = "Host(`changedetection.${domain}`)";
            service = "changedetection";
            middlewares = [ "authelia" ];
            tls = true;
          };
          freshrss = {
            rule = "Host(`rss.${domain}`)";
            service = "freshrss";
            middlewares = [ "authelia" ];
            tls = true;
          };
          jellyfin = {
            rule = "Host(`jellyfin.${domain}`)";
            service = "jellyfin";
            tls = true;
          };
          ntfy = {
            rule = "Host(`ntfy.${domain}`)";
            service = "ntfy";
            middlewares = [ "authelia" ];
            tls = true;
          };
          paperless = {
            rule = "Host(`paper.${domain}`)";
            service = "paperless";
            middlewares = [ "authelia" ];
            tls = true;
          };
          glance = {
            rule = "Host(`${domain}`)";
            service = "glance";
            tls.certResolver = "cloudflare";
            middlewares = [ "authelia" ];
          };

        };
        middlewares = {
          cf-real-ip.plugin.cf-real-ip = { };
          authelia.forwardAuth = {
            address = "http://10.231.136.7:9091/api/authz/forward-auth";
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
        };
        services = {
          hass.loadBalancer.servers = [ { url = "http://192.168.0.4"; } ];
          opencode.loadBalancer.servers = [ { url = "http://localhost:4096"; } ];
          authelia.loadBalancer.servers = [ { url = "http://10.231.136.7:9091"; } ];
          bazarr.loadBalancer.servers = [ { url = "http://10.231.136.2:6767"; } ];
          prowlarr.loadBalancer.servers = [ { url = "http://10.231.136.3:9696"; } ];
          radarr.loadBalancer.servers = [ { url = "http://10.231.136.5:7878"; } ];
          sonarr.loadBalancer.servers = [ { url = "http://10.231.136.6:8989"; } ];
          qbittorrent.loadBalancer.servers = [ { url = "http://10.231.136.4:8080"; } ];
          changedetection.loadBalancer.servers = [ { url = "http://10.231.136.8:5000"; } ];
          freshrss.loadBalancer.servers = [ { url = "http://10.231.136.9:8082"; } ];
          jellyfin.loadBalancer.servers = [ { url = "http://10.231.136.10:8096"; } ];
          ntfy.loadBalancer.servers = [ { url = "http://10.231.136.11:8090"; } ];
          paperless.loadBalancer.servers = [ { url = "http://10.231.136.12:8000"; } ];
          glance.loadBalancer.servers = [ { url = "http://10.231.136.15:8080"; } ];

        };
      };
    };
  };

  systemd.services.traefik-qbit-auth = {
    description = "Generate traefik qbit-auth middleware config";
    wantedBy = [ "multi-user.target" ];
    before = [ "traefik.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /run/traefik
      cat > /run/traefik/qbit-auth.yml <<EOF
      http:
        middlewares:
          qbit-basic-auth:
            headers:
              customRequestHeaders:
                Authorization: "Basic $(cat ${config.sops.secrets.qbittorrentAuth.path})"
      EOF
    '';
  };

  services.traefik.staticConfigOptions.providers.file.directory = "/run/traefik";

  services.ddclient = {
    enable = true;
    configFile = "${cfg.configDir}/ddclient/ddclient.conf";
  };

  containers.glance = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.15";
    bindMounts = {
      "/config" = {
        hostPath = "${cfg.configDir}/glance";
        isReadOnly = false;
      };
    };
    config =
      { ... }:
      {
        services.glance = {
          enable = true;
          settings = {
            server.assets-path = "/config/assets";
            theme = {
              background-color = lib.mkForce "50 1 6";
              primary-color = lib.mkForce "24 97 58";
              negative-color = lib.mkForce "209 88 54";
            };
            branding = {
              hide-footer = true;
              custom-footer = ''<p>Powered by <a href="https://github.com/glanceapp/glance">Glance</a></p>'';
              logo-text = "R";
              favicon-url = "/assets/favicon.png";
            };
            pages = [
              {
                name = "Home";
                hide-desktop-navigation = true;
                columns = [
                  {
                    size = "small";
                    widgets = [
                      {
                        type = "clock";
                        hide-header = true;
                        hour-format = "24h";
                      }
                      {
                        type = "weather";
                        hide-header = true;
                        location = "Moquehua, Buenos Aires, Argentina";
                        units = "metric";
                        hour-format = "24h";
                      }
                      {
                        type = "server-stats";
                        hide-header = true;
                        servers = [
                          {
                            type = "local";
                            name = "Host";
                            mountpoints = {
                              "/" = {
                                name = "SSD";
                              };
                            };
                          }
                        ];
                      }
                    ];
                  }
                  {
                    size = "full";
                    widgets = [
                      {
                        type = "monitor";
                        hide-header = true;
                        title = "Services";
                        sites = [
                          {
                            title = "Bazarr";
                            url = "http://10.231.136.2:6767";
                          }
                          {
                            title = "Prowlarr";
                            url = "http://10.231.136.3:9696";
                          }
                          {
                            title = "Radarr";
                            url = "http://10.231.136.5:7878";
                          }
                          {
                            title = "Sonarr";
                            url = "http://10.231.136.6:8989";
                          }
                          {
                            title = "Jellyfin";
                            url = "http://10.231.136.10:8096";
                          }
                          {
                            title = "Paperless";
                            url = "http://10.231.136.12:8000";
                          }
                          {
                            title = "FreshRSS";
                            url = "http://10.231.136.9:8082";
                          }
                          {
                            title = "ntfy";
                            url = "http://10.231.136.11:8090";
                          }
                        ];
                      }
                      {
                        type = "split-column";
                        widgets = [
                          {
                            type = "group";
                            widgets = [
                              { type = "hacker-news"; }
                              { type = "lobsters"; }
                            ];
                          }
                          {
                            type = "group";
                            widgets = [
                              {
                                type = "reddit";
                                subreddit = "selfhosted";
                              }
                              {
                                type = "reddit";
                                subreddit = "homelab";
                              }
                            ];
                          }
                        ];
                      }
                    ];
                  }
                  {
                    size = "small";
                    widgets = [
                      {
                        type = "bookmarks";
                        hide-header = true;
                        groups = [
                          {
                            title = "Contact";
                            color = "200 50 50";
                            links = [
                              {
                                title = "Mail";
                                url = "mailto:me@repparw.com";
                              }
                              {
                                title = "Github";
                                url = "https://github.com/repparw";
                              }
                            ];
                          }
                        ];
                      }
                      {
                        type = "markets";
                        hide-header = true;
                        chart-link-template = "https://www.tradingview.com/chart/?symbol={SYMBOL}";
                        markets = [
                          {
                            symbol = "SPY";
                            name = "S&P 500";
                          }
                          {
                            symbol = "BTC-USD";
                            name = "Bitcoin";
                          }
                          {
                            symbol = "NVDA";
                            name = "NVIDIA";
                          }
                          {
                            symbol = "AAPL";
                            name = "Apple";
                          }
                          {
                            symbol = "MSFT";
                            name = "Microsoft";
                          }
                        ];
                      }
                    ];
                  }
                ];
              }
            ];
          };
        };
        system.stateVersion = "26.05";
      };
  };
}
