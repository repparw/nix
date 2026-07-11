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
          name:
          {
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
              extraConfig
              extraFlags
              extraOptions
              ;
            name = name;
            privateUsers = "identity";
            serviceConfig = {
              ${name} = serviceConfig;
            };
            bindMounts =
              lib.optionalAttrs mediaBind {
                "/data" = {
                  hostPath = cfg.mediaPortalDir;
                  isReadOnly = false;
                };
              }
              // extraBindMounts;
          };
        mkServarrContainer = name: {
          serviceConfig = {
            enable = true;
            openFirewall = true;
            settings.server.bindAddress = "*";
            dataDir = "/config";
          };
          extraConfig = {
            environment.systemPackages = [ pkgs.striptracks ];
            services.${name}.group = "media";
            users.groups.media.gid = 900;
            systemd.services.${name}.serviceConfig.UMask = lib.mkForce "0002";
          };
          extraBindMounts = {
            "/config" = {
              hostPath = "${cfg.configDir}/${name}";
              isReadOnly = false;
            };
            "/data/torrents" = {
              hostPath = "${cfg.rootDir}/torrents";
              isReadOnly = false;
            };
          };
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

        containers = lib.mapAttrs mkArrContainer {
          bazarr = {
            serviceConfig = {
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

          prowlarr = {
            mediaBind = false;
            serviceConfig = {
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

          qbittorrent = {
            mediaBind = false;
            extraConfig = {
              nixpkgs.overlays = [
                (final: prev: {
                  qbittorrent-nox = prev.qbittorrent-nox.overrideAttrs (old: {
                    patches = (old.patches or [ ]) ++ [
                      (prev.fetchpatch {
                        url = "https://patch-diff.githubusercontent.com/raw/qbittorrent/qBittorrent/pull/24055.patch";
                        hash = "sha256-XW4ZnyaxBuIb3kny12+T/uTQOFIOVnBRV9qc1AWy6MY=";
                      })
                    ];
                  });
                })
              ];
              services.qbittorrent.group = "media";
              users.groups.media.gid = 900;
              systemd.services.qbittorrent.serviceConfig.UMask = lib.mkForce "0002";
            };
            serviceConfig = {
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

          radarr = mkServarrContainer "radarr";
          sonarr = mkServarrContainer "sonarr";
        };
      };
  };
}
