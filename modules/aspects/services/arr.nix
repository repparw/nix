{
  den,
  lib,
  ...
}:
{
  den.aspects.nixos-services.provides.arr = {
    service-registry = [
      {
        name = "bazarr";
        definition = {
          hostname = "bazarr";
          port = 6767;
          auth = "one_factor";
          container = true;
          monitor = true;
          healthcheck = "/health";
          backupRelativePath = "bazarr/backup";
        };
      }
      {
        name = "prowlarr";
        definition = {
          hostname = "prowlarr";
          port = 9696;
          auth = "one_factor";
          container = true;
          monitor = true;
          healthcheck = "/ping";
          backupRelativePath = "prowlarr/Backups";
        };
      }
      {
        name = "qbittorrent";
        definition = {
          hostname = "qbit";
          port = 8080;
          publishedPort = 18080;
          auth = "external";
          container = true;
          monitor = true;
          backupRelativePath = "qbittorrent";
        };
      }
      {
        name = "radarr";
        definition = {
          hostname = "radarr";
          port = 7878;
          auth = "one_factor";
          container = true;
          monitor = true;
          healthcheck = "/ping";
          backupRelativePath = "radarr/Backups";
        };
      }
      {
        name = "sonarr";
        definition = {
          hostname = "sonarr";
          port = 8989;
          auth = "one_factor";
          container = true;
          monitor = true;
          healthcheck = "/ping";
          backupRelativePath = "sonarr/Backups";
        };
      }
    ];

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
                # Bind the portal PARENT, not its automount submounts. The
                # recursive bind shares the autofs instances with the
                # container: reads keep the media mounts alive, and when the
                # containers are idle the submounts expire and unmount inside
                # the running container, so the disks can spin down without
                # stopping anything. Binding the submounts directly pins the
                # filesystem and turns every idle expiry into a container
                # stop - see f99a21793.
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
            # /data/torrents comes from the parent portal bind once the host
            # dir lives at mediaPortalDir/torrents. Do not add a nested bind
            # here: a bind whose target sits inside the parent bind's tree is
            # what f99a21793 had to flatten away.
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
            # bazarr writes subtitle sidecars next to the media, so it needs
            # the media group like sonarr/radarr. See mkServarrContainer.
            extraConfig = {
              systemd.tmpfiles.rules = [ ];
              services.bazarr.group = "media";
              users.groups.media.gid = 900;
              systemd.services.bazarr.serviceConfig.UMask = lib.mkForce "0002";
            };
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
            # Prowlarr is the only Arr container that opts out of
            # mkServarrContainer, so it misses the media group the others get.
            # The servarr module runs it as DynamicUser, and systemd recycles
            # the allocated gid once the unit stops, so pinning Group= to the
            # static media group is what keeps the bind-mounted Backups tree
            # writable across restarts. The systemd property is set directly
            # because the prowlarr module exposes no group option.
            # Directory modes only (2775): a recursive mode would set the exec
            # bit on the stored zips/db.
            extraConfig = {
              users.groups.media.gid = 900;
              systemd.services.prowlarr.serviceConfig.Group = "media";
              systemd.services.prowlarr.serviceConfig.UMask = lib.mkForce "0002";
              systemd.tmpfiles.rules = [
                "d /var/lib/private/prowlarr/Backups 2775 root media -"
                "d /var/lib/private/prowlarr/Backups/scheduled 2775 root media -"
                "d /var/lib/private/prowlarr/Backups/manual 2775 root media -"
              ];
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
              # Flat bind of the torrents dir inside the portal tree; not
              # nested under a parent media bind (see mkServarrContainer).
              "/data/torrents" = {
                hostPath = "${cfg.mediaPortalDir}/torrents";
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
