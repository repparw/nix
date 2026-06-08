{
  den,
  lib,
  ...
}:
{
  den.aspects.nixos-services.provides.arr = {
    nixos =
      { config, pkgs, ... }:
      let
        cfg = config.modules.services;
        mkArrContainer =
          {
            ipOctet,
            serviceConfig,
            mediaBind ? true,
            extraBindMounts ? { },
            extraOptions ? { },
            extraConfig ? { },
            extraFlags ? [ ],
          }:
          {
            autoStart = true;
            privateNetwork = true;
            hostAddress = "10.231.136.1";
            localAddress = "10.231.136.${toString ipOctet}";
            inherit extraFlags;
            bindMounts =
              lib.optionalAttrs mediaBind {
                "/data" = {
                  hostPath = cfg.mediaPortalDir;
                  isReadOnly = false;
                };
              }
              // extraBindMounts;
            config =
              { ... }:
              lib.mkMerge [
                {
                  services = serviceConfig;
                  system.stateVersion = "26.05";
                  networking.useHostResolvConf = false;
                  networking.nameservers = [ "10.231.136.1" ];
                }
                extraConfig
              ];
          }
          // extraOptions;
      in
      {
        containers.bazarr = mkArrContainer {
          ipOctet = 2;
          extraOptions.privateUsers = "identity";
          serviceConfig.bazarr = {
            enable = true;
            openFirewall = true;
            dataDir = "/config";
          };
          extraConfig.systemd.tmpfiles.rules = [ ];
          extraBindMounts = {
            "/config" = {
              hostPath = "${cfg.configDir}/bazarr";
              isReadOnly = false;
            };
          };
        };

        containers.prowlarr = mkArrContainer {
          ipOctet = 3;
          mediaBind = false;
          extraOptions.privateUsers = "identity";
          serviceConfig.prowlarr = {
            enable = true;
            openFirewall = true;
          };
          extraBindMounts = {
            "/var/lib/private/prowlarr/Backups" = {
              hostPath = "${cfg.configDir}/prowlarr/Backups";
              isReadOnly = false;
            };
          };
        };

        containers.qbittorrent = mkArrContainer {
          ipOctet = 4;
          mediaBind = false;
          extraOptions.privateUsers = "identity";
          extraConfig.nixpkgs.overlays = [
            (final: prev: {
              qbittorrent-nox = prev.qbittorrent-nox.overrideAttrs (old: {
                patches = (old.patches or [ ]) ++ [
                  (prev.fetchpatch {
                    url = "https://patch-diff.githubusercontent.com/raw/qbittorrent/qBittorrent/pull/24055.patch";
                    hash = "sha256-rhnnxa6pmXSs3rt94FrAObbtH+vYOb+kFvOTcwmbHl8=";
                  })
                ];
              });
            })
          ];
          serviceConfig.qbittorrent = {
            enable = true;
            openFirewall = true;
            torrentingPort = 54535;
          };
          extraOptions.forwardPorts = [
            {
              protocol = "tcp";
              hostPort = 54535;
              containerPort = 54535;
            }
            {
              protocol = "udp";
              hostPort = 54535;
              containerPort = 54535;
            }
          ];
          extraBindMounts = {
            "/var/lib/qBittorrent/qBittorrent" = {
              hostPath = "${cfg.configDir}/qbittorrent";
              isReadOnly = false;
            };
            "/data/torrents" = {
              hostPath = "${cfg.rootDir}/torrents";
              isReadOnly = false;
            };
          };
        };

        containers.radarr = mkArrContainer {
          ipOctet = 5;
          extraOptions.privateUsers = "identity";
          serviceConfig.radarr = {
            enable = true;
            openFirewall = true;
            settings.server.bindAddress = "*";
            dataDir = "/config";
          };
          extraConfig = {
            environment.systemPackages = [ pkgs.striptracks ];
            systemd.tmpfiles.rules = [ ];
            systemd.services.radarr.serviceConfig.PrivateUsers = lib.mkForce false;
          };
          extraBindMounts = {
            "/config" = {
              hostPath = "${cfg.configDir}/radarr";
              isReadOnly = false;
            };
          };
        };

        containers.sonarr = mkArrContainer {
          ipOctet = 6;
          extraOptions.privateUsers = "identity";
          serviceConfig.sonarr = {
            enable = true;
            openFirewall = true;
            settings.server.bindAddress = "*";
            dataDir = "/config";
          };
          extraConfig = {
            environment.systemPackages = [ pkgs.striptracks ];
            systemd.tmpfiles.rules = [ ];
            systemd.services.sonarr.serviceConfig.PrivateUsers = lib.mkForce false;
          };
          extraBindMounts = {
            "/config" = {
              hostPath = "${cfg.configDir}/sonarr";
              isReadOnly = false;
            };
          };
        };
      };
  };
}
