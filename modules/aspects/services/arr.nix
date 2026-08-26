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
            forwardPorts ? [ ],
          }:
          servicesLib.mkContainer {
            inherit
              cfg
              extraConfig
              extraFlags
              extraOptions
              forwardPorts
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
        containers = lib.mapAttrs mkArrContainer {
          bazarr = {
            serviceConfig = {
              enable = true;
              openFirewall = true;
              dataDir = "/config";
            };
            extraConfig.systemd.tmpfiles.rules = [ ];
            # Publish the WebUI onto alpha's LAN so remote ingress can target
            # it (containers bridge out via NAT only; see _services/inventory.nix).
            forwardPorts = [
              {
                protocol = "tcp";
                hostPort = 6767;
                containerPort = 6767;
              }
            ];
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
            forwardPorts = [
              {
                protocol = "tcp";
                hostPort = 9696;
                containerPort = 9696;
              }
            ];
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
                    # TODO: Remove this patch once qBittorrent PR #24055 lands
                    # in a release covered by Nixpkgs.
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
              systemd.services.qbittorrent.preStart = lib.mkBefore ''
                rm -f /var/lib/qBittorrent/qBittorrent/config/lockfile
              '';
              systemd.services.qbittorrent.serviceConfig.UMask = lib.mkForce "0002";
            };
            serviceConfig = {
              enable = true;
              openFirewall = true;
              torrentingPort = 54535;
            };
            forwardPorts = [
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
              # Published WebUI (remapped: glance owns 8080 on the LAN iface).
              {
                protocol = "tcp";
                hostPort = 18080;
                containerPort = 8080;
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

          radarr = (mkServarrContainer "radarr") // {
            forwardPorts = [
              {
                protocol = "tcp";
                hostPort = 7878;
                containerPort = 7878;
              }
            ];
          };
          sonarr = (mkServarrContainer "sonarr") // {
            forwardPorts = [
              {
                protocol = "tcp";
                hostPort = 8989;
                containerPort = 8989;
              }
            ];
          };
        };
      };
  };
}
