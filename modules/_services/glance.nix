{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.services;
  servicesLib = import ./lib.nix { inherit lib pkgs; };
  service = cfg.definitions.glance;
  glanceAssets = pkgs.runCommand "glance-assets" { } ''
    mkdir -p $out
    cp ${./glance-favicon.svg} $out/favicon.svg
  '';
in
{
  containers.glance = servicesLib.mkContainer {
    inherit cfg;
    name = "glance";
    privateUsers = "pick";
    bindMounts = {
      "/assets" = {
        hostPath = "${glanceAssets}";
        isReadOnly = true;
      };
    };
    extraConfig = {
      services.glance = {
        enable = true;
        openFirewall = true;
        settings = {
          server = {
            host = "0.0.0.0";
            port = service.port;
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
                      sites = servicesLib.monitorSites cfg;
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
                              title = "r/selfhosted";
                              feeds = [
                                {
                                  url = "https://www.reddit.com/r/selfhosted/.rss";
                                  # reddit fingerprint-blocks non-browser clients
                                  # and rate-limits concurrent .rss per IP, so a
                                  # browser UA is required and two subreddits may
                                  # not both load on the same fetch cycle.
                                  headers."User-Agent" = "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0";
                                }
                              ];
                            }
                            {
                              type = "rss";
                              title = "r/homelab";
                              feeds = [
                                {
                                  url = "https://www.reddit.com/r/homelab/.rss";
                                  headers."User-Agent" = "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0";
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
    };
  };
}
