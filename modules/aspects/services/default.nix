{
  den,
  inputs,
  lib,
  ...
}:
{
  den.aspects.nixos-services = {
    includes = with den.aspects.nixos-services._; [
      archisteamfarm
      arr
      automations
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
        servicesLib = import ../../_services/lib.nix { inherit lib pkgs; };
      in
      {
        imports = [
          (import ../../_services/authelia.nix {
            inherit
              cfg
              config
              lib
              pkgs
              servicesLib
              ;
          })
          (import ../../_services/miniflux.nix {
            inherit
              cfg
              config
              lib
              pkgs
              servicesLib
              ;
          })
          (import ../../_services/paperless.nix {
            inherit
              cfg
              config
              lib
              pkgs
              servicesLib
              ;
          })
          (import ../../_services/ddclient.nix {
            inherit
              cfg
              config
              lib
              pkgs
              servicesLib
              ;
          })
          (import ../../_services/proxy.nix {
            inherit
              cfg
              config
              lib
              pkgs
              servicesLib
              ;
          })
          (import ../../_services/glance.nix {
            inherit
              cfg
              config
              lib
              pkgs
              servicesLib
              ;
          })
          ../../service-definitions.nix
        ];

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
            })
          ];

          networking.hosts."192.168.0.18" = servicesLib.serviceHosts cfg ++ [
            cfg.domain
            "code.${cfg.domain}"
            "home.${cfg.domain}"
          ];

          systemd.services = servicesLib.containerBackupAfters cfg;

          fileSystems = servicesLib.backupMounts cfg // {
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
