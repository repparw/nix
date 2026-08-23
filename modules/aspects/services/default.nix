{ den, ... }:
{
  den.aspects.nixos-services = {
    includes =
      with den.aspects.nixos-services._;
      [
        archisteamfarm
        arr
        automations
        iebApi
        jellyfin
        matrizApi
      ]
      ++ [ den.aspects.lan-hosts ];

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
        # The public edge (proxy/authelia/ddclient) moved to pi; this host
        # keeps only its backend services plus the shared schema they use.
        imports = [
          ../../_services/miniflux.nix
          ../../_services/paperless.nix
          ../../_services/glance.nix
          ../../service-definitions.nix
        ];

        config = {
          modules.services.hostAddresses = {
            pi = "192.168.0.4";
          };

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

          users.groups.media = {
            gid = 900;
            members = [ config.users.users.repparw.name ];
          };

          services.resolved.settings.Resolve.DNSStubListenerExtra = "0.0.0.0";

          nixpkgs.overlays = [
            (final: prev: {
              striptracks = final.callPackage ../../_packages/striptracks.nix { };
            })
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
