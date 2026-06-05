{
  cfg,
  config,
  lib,
  pkgs,
  ...
}:
let
  glanceAssets = pkgs.runCommand "glance-assets" { } ''
    mkdir -p $out
    cp ${./glance-favicon.svg} $out/favicon.svg
  '';
in
{
  containers.glance = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.15";
    bindMounts = {
      "/assets" = {
        hostPath = "${glanceAssets}";
        isReadOnly = true;
      };
    };
    config =
      { ... }:
      {
        networking.useHostResolvConf = false;
        networking.nameservers = [ "10.231.136.1" ];

        services.glance = {
          enable = true;
          openFirewall = true;
          settings = {
            server = {
              host = "0.0.0.0";
              assets-path = "/assets";
            };
            theme = {
              background-color = lib.mkForce "50 1 6";
              primary-color = lib.mkForce "24 97 58";
              negative-color = lib.mkForce "209 88 54";
            };
            branding = {
              hide-footer = true;
              custom-footer = ''<p>Powered by <a href="https://github.com/glanceapp/glance">Glance</a></p>'';
              logo-text = "R";
              favicon-url = "/assets/favicon.svg";
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
                              "/config" = {
                                hide = true;
                              };
                              "/nix/store" = {
                                hide = true;
                              };
                              "/nix/var/nix/daemon-socket" = {
                                hide = true;
                              };
                              "/nix/var/nix/db" = {
                                hide = true;
                              };
                              "/nix/var/nix/gcroots" = {
                                hide = true;
                              };
                              "/nix/var/nix/profiles" = {
                                hide = true;
                              };
                              "/run/host/os-release" = {
                                hide = true;
                              };
                              "/etc/localtime" = {
                                hide = true;
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
                            title = "bazarr";
                            url = "https://bazarr.${cfg.domain}";
                            check-url = "http://${config.containers.bazarr.localAddress}:6767";
                          }
                          {
                            title = "prowlarr";
                            url = "https://prowlarr.${cfg.domain}";
                            check-url = "http://${config.containers.prowlarr.localAddress}:9696";
                          }
                          {
                            title = "radarr";
                            url = "https://radarr.${cfg.domain}";
                            check-url = "http://${config.containers.radarr.localAddress}:7878";
                          }
                          {
                            title = "sonarr";
                            url = "https://sonarr.${cfg.domain}";
                            check-url = "http://${config.containers.sonarr.localAddress}:8989";
                          }
                          {
                            title = "jellyfin";
                            url = "https://jellyfin.${cfg.domain}";
                            check-url = "http://${config.containers.jellyfin.localAddress}:8096";
                          }
                          {
                            title = "paperless";
                            url = "https://paper.${cfg.domain}";
                            check-url = "http://${config.containers.paperless.localAddress}:8000";
                          }
                          {
                            title = "miniflux";
                            url = "https://rss.${cfg.domain}";
                            check-url = "http://10.231.136.1:8081";
                          }
                          {
                            title = "ntfy";
                            url = "https://ntfy.${cfg.domain}";
                            check-url = "http://${config.containers.ntfy.localAddress}:8090";
                          }
                          {
                            title = "changedetection";
                            url = "https://changedetection.${cfg.domain}";
                            check-url = "http://${config.containers.changedetection.localAddress}:5000";
                          }
                          {
                            title = "authelia";
                            url = "https://auth.${cfg.domain}";
                            check-url = "http://${config.containers.authelia.localAddress}:9091";
                          }
                          {
                            title = "qbit";
                            url = "https://qbit.${cfg.domain}";
                            check-url = "http://${config.containers.qbittorrent.localAddress}:8080";
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
                                type = "rss";
                                title = "Reddit";
                                feeds = [
                                  {
                                    url = "https://www.reddit.com/r/selfhosted/.rss";
                                    title = "r/selfhosted";
                                  }
                                  {
                                    url = "https://www.reddit.com/r/homelab/.rss";
                                    title = "r/homelab";
                                  }
                                ];
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

  systemd.services."container@glance".preStart = "mkdir -p ${cfg.configDir}/glance/assets";
}
