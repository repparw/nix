{ den, ... }:
{
  # Common contract for every host that runs or consumes fleet services.
  # Service selection is deliberately separate so a small host can use the
  # schema and allocator without pulling Alpha's media closures.
  den.aspects.service-host.nixos =
    {
      config,
      lib,
      service-registry,
      ...
    }:
    let
      entries = map (
        entry:
        let
          service = entry.value;
          definition = service.definition;
          resolvedDefinition =
            removeAttrs definition [ "backupRelativePath" ]
            // lib.optionalAttrs (definition ? backupRelativePath) {
              backup.path = "${config.modules.services.configDir}/${definition.backupRelativePath}";
            };
        in
        {
          inherit (service) name;
          value = resolvedDefinition // {
            host = entry.source.host.name;
          };
        }
      ) service-registry;
      names = map (entry: entry.name) entries;
      generatedDefinitions =
        if builtins.length names != builtins.length (lib.unique names) then
          throw "duplicate service registry entries: ${lib.concatStringsSep ", " names}"
        else
          builtins.listToAttrs entries;
      definitions = lib.mapAttrs (_: lib.mkDefault) generatedDefinitions;
    in
    {
      imports = [
        ../../service-definitions.nix
        ../../_services/address-allocator.nix
      ];

      modules.services = {
        inherit definitions;
        hostAddresses = {
          alpha = "192.168.0.18";
          pi = "192.168.0.4";
          epsilon = "10.5.5.3";
        };
      };
    };

  den.aspects.media-stack = {
    service-registry = [
      {
        name = "paperless";
        definition = {
          hostname = "paper";
          port = 8000;
          auth = "one_factor";
          container = true;
          monitor = true;
          backupRelativePath = "paperless/export";
        };
      }
    ];

    includes =
      with den.aspects.nixos-services._;
      [
        arr
        jellyfin
        matrizApi
      ]
      ++ [
        den.aspects.service-host
        den.aspects.lan-hosts
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
        # Backup mounts only for services this host actually runs: the
        # shared inventory also carries pi-local services whose state never
        # exists here.
        localBackupCfg = cfg // {
          definitions = lib.filterAttrs (_: service: service.host == cfg.hostName) cfg.definitions;
        };
      in
      {
        imports = [ ../../_services/paperless.nix ];

        config = {
          networking = {
            nat = {
              enable = true;
              internalInterfaces = [ "ve-*" ];
            };
            firewall.extraInputRules = ''
              iifname "ve-*" ip daddr ${cfg.bridgePrefix}.1 tcp dport 53 accept
              iifname "ve-*" ip daddr ${cfg.bridgePrefix}.1 udp dport 53 accept
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

          systemd.services = servicesLib.containerBackupAfters localBackupCfg;

          fileSystems = servicesLib.backupMounts localBackupCfg // {
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
                "x-gvfs-notrash"
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
                "x-gvfs-notrash"
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
