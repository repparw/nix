{
  cfg,
  config,
  lib,
  ...
}:
{
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
          openFirewall = true;
          settings = {
            server = {
              host = "0.0.0.0";
              assets-path = "/config/assets";
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
                            url = "http://${config.containers.bazarr.localAddress}:6767";
                          }
                          {
                            title = "Prowlarr";
                            url = "http://${config.containers.prowlarr.localAddress}:9696";
                          }
                          {
                            title = "Radarr";
                            url = "http://${config.containers.radarr.localAddress}:7878";
                          }
                          {
                            title = "Sonarr";
                            url = "http://${config.containers.sonarr.localAddress}:8989";
                          }
                          {
                            title = "Jellyfin";
                            url = "http://${config.containers.jellyfin.localAddress}:8096";
                          }
                          {
                            title = "Paperless";
                            url = "http://${config.containers.paperless.localAddress}:8000";
                          }
                          {
                            title = "FreshRSS";
                            url = "http://${config.containers.freshrss.localAddress}:8082";
                          }
                          {
                            title = "ntfy";
                            url = "http://${config.containers.ntfy.localAddress}:8090";
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
