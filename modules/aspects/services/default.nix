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

      # The registry provenance carries the complete originating host entity.
      # Keep the service-reachable address with fleet topology and derive the
      # compatibility map here instead of maintaining a second host registry.
      hostAddresses = builtins.listToAttrs (
        map (entry: {
          name = entry.source.host.name;
          value =
            entry.source.host.serviceAddress
              or (throw "service host ${entry.source.host.name} is missing serviceAddress topology metadata");
        }) service-registry
      );
    in
    {
      imports = [
        ../../service-definitions.nix
        ../../_services/address-allocator.nix
      ];

      modules.services = {
        inherit definitions hostAddresses;
      };
    };

  den.aspects.media-stack = {
    includes =
      with den.aspects.nixos-services._;
      [
        arr
        jellyfin
        matrizApi
        paperless
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
