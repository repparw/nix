{ lib, ... }:
{
  den.aspects.nixos-services = {
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
          (import ../_services/arr.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../_services/authelia.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../_services/changedetection.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../_services/miniflux.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../_services/jellyfin.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../_services/ntfy.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../_services/paperless.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../_services/ddclient.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../_services/proxy.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../_services/glance.nix {
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
            default = "${cfg.rootDir}/data";
          };

          externalDataDir = lib.mkOption {
            type = lib.types.path;
            default = "/mnt/seagate";
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

          services.resolved.settings.Resolve.DNSStubListenerExtra = "0.0.0.0";

          nixpkgs.overlays = [
            (final: prev: {
              striptracks = final.callPackage ../_packages/striptracks.nix { };
              mercury-parser-api = final.callPackage ../_packages/mercury-parser.nix { };
            })
          ];

          networking.hosts."192.168.0.18" = [
            cfg.domain
            "auth.${cfg.domain}"
            "bazarr.${cfg.domain}"
            "changedetection.${cfg.domain}"
            "glance.${cfg.domain}"
            "home.${cfg.domain}"
            "jellyfin.${cfg.domain}"
            "ntfy.${cfg.domain}"
            "paper.${cfg.domain}"
            "prowlarr.${cfg.domain}"
            "qbit.${cfg.domain}"
            "radarr.${cfg.domain}"
            "rss.${cfg.domain}"
            "sonarr.${cfg.domain}"
          ];

          fileSystems = lib.mkMerge [
            {
              "${cfg.backupDir}/bazarr" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/bazarr/backup";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=60"
                  "nofail"
                ];
              };
              "${cfg.backupDir}/authelia" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/authelia";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=60"
                  "nofail"
                ];
              };
              "${cfg.backupDir}/changedetection" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/changedetection";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=60"
                  "nofail"
                ];
              };
              "${cfg.backupDir}/miniflux" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/miniflux";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=60"
                  "nofail"
                ];
              };
              "${cfg.backupDir}/jellyfin" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/jellyfin/data/data/backups";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=60"
                  "nofail"
                ];
              };
              "${cfg.backupDir}/ntfy" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/ntfy";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=60"
                  "nofail"
                ];
              };
              "${cfg.backupDir}/paper" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/paper/export";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=60"
                  "nofail"
                ];
              };
              "${cfg.backupDir}/prowlarr" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/prowlarr/Backups";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=60"
                  "nofail"
                ];
              };
              "${cfg.backupDir}/qbittorrent" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/qbittorrent";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=60"
                  "nofail"
                ];
              };
              "${cfg.backupDir}/radarr" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/radarr/Backups";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=60"
                  "nofail"
                ];
              };
              "${cfg.backupDir}/sonarr" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/sonarr/Backups";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=60"
                  "nofail"
                ];
              };
              "${cfg.backupDir}/traefik" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/traefik";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=60"
                  "nofail"
                ];
              };
            }
          ];
        };
      };
  };
}
