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
          (import ../_services/freshrss.nix {
            inherit
              cfg
              config
              lib
              pkgs
              ;
          })
          (import ../_services/grafana.nix {
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
          (import ../_services/prometheus.nix {
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
          networking.hosts."192.168.0.18" = [
            cfg.domain
            "auth.${cfg.domain}"
            "bazarr.${cfg.domain}"
            "changedetection.${cfg.domain}"
            "glance.${cfg.domain}"
            "grafana.${cfg.domain}"
            "home.${cfg.domain}"
            "jellyfin.${cfg.domain}"
            "logs.${cfg.domain}"
            "ntfy.${cfg.domain}"
            "paper.${cfg.domain}"
            "prowlarr.${cfg.domain}"
            "prometheus.${cfg.domain}"
            "qbit.${cfg.domain}"
            "radarr.${cfg.domain}"
            "rss.${cfg.domain}"
            "sonarr.${cfg.domain}"
          ];

          fileSystems = lib.mkMerge [
            {
              "/home/repparw/.config/dlsuite/bazarr" = {
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
              "/home/repparw/.config/dlsuite/authelia" = {
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
              "/home/repparw/.config/dlsuite/changedetection" = {
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
              "/home/repparw/.config/dlsuite/freshrss" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/freshrss";
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
              "/home/repparw/.config/dlsuite/glance" = {
                depends = [ "/" ];
                device = "${cfg.configDir}/glance";
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
              "/home/repparw/.config/dlsuite/jellyfin" = {
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
              "/home/repparw/.config/dlsuite/ntfy" = {
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
              "/home/repparw/.config/dlsuite/paper" = {
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
              "/home/repparw/.config/dlsuite/prowlarr" = {
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
              "/home/repparw/.config/dlsuite/qbittorrent" = {
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
              "/home/repparw/.config/dlsuite/radarr" = {
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
              "/home/repparw/.config/dlsuite/sonarr" = {
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
              "/home/repparw/.config/dlsuite/traefik" = {
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
