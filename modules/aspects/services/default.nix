{
  den,
  inputs,
  lib,
  ...
}:
{
  flake-file.inputs.hermes-agent = {
    url = "github:NousResearch/hermes-agent";
    inputs.nixpkgs.follows = "nixpkgs";
  };

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
          (import ../../_services/hermes.nix {
            inherit
              cfg
              config
              inputs
              lib
              pkgs
              ;
          })
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
            cfg.domain
            "auth.${cfg.domain}"
            "bazarr.${cfg.domain}"
            "code.${cfg.domain}"
            "glance.${cfg.domain}"
            "home.${cfg.domain}"
            "jellyfin.${cfg.domain}"
            "paper.${cfg.domain}"
            "prowlarr.${cfg.domain}"
            "qbit.${cfg.domain}"
            "radarr.${cfg.domain}"
            "rss.${cfg.domain}"
            "sonarr.${cfg.domain}"
          ];

          fileSystems = lib.mkMerge [
            {
              "${cfg.mediaPortalDir}/hdd" = {
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
              "${cfg.mediaPortalDir}/seagate" = {
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
              "${cfg.backupDir}/bazarr" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/bazarr/backup";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
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
                  "nofail"
                ];
              };
              "${cfg.backupDir}/archisteamfarm" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/archisteamfarm";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
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
                  "nofail"
                ];
              };
              "${cfg.backupDir}/jellyfin" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/jellyfin/data/backups";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
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
                  "nofail"
                ];
              };
            }
          ];

          systemd.tmpfiles.rules = [
            "d ${cfg.mediaPortalDir} 0755 root root - -"
            "d ${cfg.mediaPortalDir}/hdd 0755 root root - -"
            "d ${cfg.mediaPortalDir}/seagate 0755 root root - -"
            "d ${cfg.configDir}/archisteamfarm 0755 root root - -"
            "d ${cfg.rootDir}/torrents 2770 root media - -"
          ];

          systemd.services = {
            "container@bazarr".after = [ "home-containers-backup-bazarr.mount" ];
            "container@authelia".after = [ "home-containers-backup-authelia.mount" ];
            "container@archisteamfarm".after = [ "home-containers-backup-archisteamfarm.mount" ];
            miniflux.after = [ "home-containers-backup-miniflux.mount" ];
            "container@jellyfin".after = [ "home-containers-backup-jellyfin.mount" ];
            "container@paperless".after = [ "home-containers-backup-paper.mount" ];
            "container@prowlarr".after = [ "home-containers-backup-prowlarr.mount" ];
            "container@qbittorrent".after = [ "home-containers-backup-qbittorrent.mount" ];
            "container@radarr".after = [ "home-containers-backup-radarr.mount" ];
            "container@sonarr".after = [ "home-containers-backup-sonarr.mount" ];
          };
        };
      };
  };
}
