{
  den,
  lib,
  ...
}:
{
  den.aspects.nixos-services = {
    includes = with den.aspects.nixos-services._; [
      archisteamfarm
      arr
      jellyfin
    ];

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.modules.services;
      in
      {
        imports = [
          (import ../../_services/authelia.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../../_services/miniflux.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../../_services/paperless.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../../_services/ddclient.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../../_services/proxy.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../../_services/glance.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
        ];

        options.modules.services = {
          rootDir = lib.mkOption {
            type = lib.types.path;
            default = "/home/containers";
          };

          dataDir = lib.mkOption {
            type = lib.types.path;
            default = "/mnt/hdd/media";
          };

          externalDataDir = lib.mkOption {
            type = lib.types.path;
            default = "/mnt/seagate";
          };

          mediaPortalDir = lib.mkOption {
            type = lib.types.path;
            default = "${cfg.rootDir}/media";
          };

          configDir = lib.mkOption {
            type = lib.types.path;
            default = "${cfg.rootDir}/config";
          };

          backupDir = lib.mkOption {
            type = lib.types.path;
            default = "${cfg.rootDir}/backup";
          };

          timezone = lib.mkOption {
            type = lib.types.str;
            default = "America/Argentina/Buenos_Aires";
          };

          domain = lib.mkOption {
            type = lib.types.str;
            default = "repparw.com";
          };
        };

        config = {
          networking = {
            nat = {
              enable = true;
              internalInterfaces = [ "ve-*" ];
            };
            firewall.extraInputRules = ''
              iifname "ve-*" ip daddr 10.231.136.1 tcp dport 53 accept
              iifname "ve-*" ip daddr 10.231.136.1 udp dport 53 accept
              iifname "ve-*" accept comment "trust container interfaces"
            '';
          };

          users.groups.media.gid = 900;

          services.resolved.settings.Resolve.DNSStubListenerExtra = "0.0.0.0";

          nixpkgs.overlays = [
            (final: prev: {
              striptracks = final.callPackage ../../_packages/striptracks.nix { };
              mercury-parser-api = final.callPackage ../../_packages/mercury-parser.nix { };
            })
          ];

          networking.hosts."192.168.0.18" = [
            "code.${cfg.domain}"
            "home.${cfg.domain}"
          ];

          fileSystems."${cfg.mediaPortalDir}/hdd" = {
            depends = [ "/" ];
            device = cfg.dataDir;
            fsType = "none";
            options = [
              "bind"
              "nofail"
              "noauto"
              "x-systemd.automount"
              "x-systemd.idle-timeout=10min"
            ];
          };
          fileSystems."${cfg.mediaPortalDir}/seagate" = {
            depends = [ "/" ];
            device = cfg.externalDataDir;
            fsType = "none";
            options = [
              "bind"
              "nofail"
              "noauto"
              "x-systemd.automount"
              "x-systemd.idle-timeout=10min"
            ];
          };

          systemd.tmpfiles.rules = [
            "d ${cfg.mediaPortalDir} 0755 root root - -"
            "d ${cfg.mediaPortalDir}/hdd 0755 root root - -"
            "d ${cfg.mediaPortalDir}/seagate 0755 root root - -"
            "d ${cfg.rootDir}/torrents 2770 root media - -"
          ];
        };
      };
  };
}
