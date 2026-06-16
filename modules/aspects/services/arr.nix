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
        servicesLib = import ../../_services/lib.nix { inherit lib pkgs; };
        mkArrContainer =
          {
            serviceName,
            serviceConfig,
            mediaBind ? true,
            extraBindMounts ? { },
            extraOptions ? { },
            extraConfig ? { },
            extraFlags ? [ ],
          }:
          servicesLib.mkContainer {
            inherit
              cfg
              serviceConfig
              extraConfig
              extraFlags
              extraOptions
              ;
            name = serviceName;
            bindMounts =
              lib.optionalAttrs mediaBind {
                "/data" = {
                  hostPath = cfg.mediaPortalDir;
                  isReadOnly = false;
                };
              }
              // extraBindMounts;
          };
      in
      {
        modules.services.inventory = {
          bazarr = {
            hostname = "bazarr";
            containerAddress = "10.231.136.2";
            port = 6767;
            auth = "one_factor";
            backup.path = "${cfg.configDir}/bazarr/backup";
            monitor = true;
          };
          prowlarr = {
            hostname = "prowlarr";
            containerAddress = "10.231.136.3";
            port = 9696;
            auth = "one_factor";
            backup.path = "${cfg.configDir}/prowlarr/Backups";
            monitor = true;
          };
          qbittorrent = {
            hostname = "qbit";
            title = "qbit";
            containerAddress = "10.231.136.4";
            port = 8080;
            auth = "external";
            backup.path = "${cfg.configDir}/qbittorrent";
            monitor = true;
          };
          radarr = {
            hostname = "radarr";
            containerAddress = "10.231.136.5";
            port = 7878;
            auth = "one_factor";
            backup.path = "${cfg.configDir}/radarr/Backups";
            monitor = true;
          };
          sonarr = {
            hostname = "sonarr";
            containerAddress = "10.231.136.6";
            port = 8989;
            auth = "one_factor";
            backup.path = "${cfg.configDir}/sonarr/Backups";
            monitor = true;
          };
        };

        containers.bazarr = mkArrContainer {
          serviceName = "bazarr";
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
          serviceName = "prowlarr";
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
          serviceName = "qbittorrent";
          mediaBind = false;
          extraOptions.privateUsers = "identity";
          extraConfig = {
            nixpkgs.overlays = [
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
            services.qbittorrent.group = "media";
            users.groups.media.gid = 900;
            systemd.services.qbittorrent.serviceConfig.UMask = lib.mkForce "0002";
          };
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
          serviceName = "radarr";
          extraOptions.privateUsers = "identity";
          serviceConfig.radarr = {
            enable = true;
            openFirewall = true;
            settings.server.bindAddress = "*";
            dataDir = "/config";
          };
          extraConfig = {
            environment.systemPackages = [ pkgs.striptracks ];
            services.radarr.group = "media";
            users.groups.media.gid = 900;
            systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";
          };
          extraBindMounts = {
            "/config" = {
              hostPath = "${cfg.configDir}/radarr";
              isReadOnly = false;
            };
            "/data/torrents" = {
              hostPath = "${cfg.rootDir}/torrents";
              isReadOnly = false;
            };
          };
        };

        containers.sonarr = mkArrContainer {
          serviceName = "sonarr";
          extraOptions.privateUsers = "identity";
          serviceConfig.sonarr = {
            enable = true;
            openFirewall = true;
            settings.server.bindAddress = "*";
            dataDir = "/config";
          };
          extraConfig = {
            environment.systemPackages = [ pkgs.striptracks ];
            services.sonarr.group = "media";
            users.groups.media.gid = 900;
            systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";
          };
          extraBindMounts = {
            "/config" = {
              hostPath = "${cfg.configDir}/sonarr";
              isReadOnly = false;
            };
            "/data/torrents" = {
              hostPath = "${cfg.rootDir}/torrents";
              isReadOnly = false;
            };
          };
        };
      };
  };
}
