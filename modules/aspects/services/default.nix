{ den, ... }:
{
  den.aspects.service-host.nixos =
    {
      config,
      lib,
      pkgs,
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

      hostMeta = builtins.listToAttrs (
        map (entry: {
          name = entry.source.host.name;
          value = entry.source.host;
        }) service-registry
      );
      hostAddresses = lib.mapAttrs (
        name: host:
        host.serviceAddress or (throw "service host ${name} is missing serviceAddress topology metadata")
      ) hostMeta;
      hostSshAddresses = lib.mapAttrs (
        name: host:
        host.sshAddress or host.serviceAddress
          or (throw "service host ${name} is missing sshAddress and serviceAddress topology metadata")
      ) hostMeta;
      svc = config.modules.services;
      domain = svc.domain;
      lanIp =
        hostSshAddresses.${svc.lanEdgeHost} or (throw "lanEdgeHost ${svc.lanEdgeHost} missing ssh address");
      publicIp =
        hostSshAddresses.${svc.publicEdgeHost}
          or (throw "publicEdgeHost ${svc.publicEdgeHost} missing ssh address");
      vhosts = lib.filterAttrs (_: service: (service.hostname or null) != null) generatedDefinitions;
      fqdn = service: "${service.hostname}.${domain}";
      lanNames = lib.mapAttrsToList (_: fqdn) (
        lib.filterAttrs (_: service: service.lanEdge or false) vhosts
      );
      publicNames = [
        domain
      ]
      ++ lib.mapAttrsToList (_: fqdn) (lib.filterAttrs (_: service: !(service.lanEdge or false)) vhosts);
      rendered = ''
        ${lib.optionalString (lanNames != [ ]) "${lanIp} ${lib.concatStringsSep " " lanNames}"}
        ${publicIp} ${lib.concatStringsSep " " publicNames}
      '';
    in
    {
      imports = [
        ../../service-definitions.nix
        ../../_services/address-allocator.nix
      ];

      options.modules.lan-hosts.file = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "Rendered hosts fragment for external consumers (TV deployment).";
      };

      config = {
        modules.services = {
          inherit definitions hostAddresses hostSshAddresses;
        };

        modules.lan-hosts.file = pkgs.writeText "lan-hosts" rendered;

        networking.hosts = lib.mkIf (config.networking.hostName != svc.publicEdgeHost) {
          ${lanIp} = lanNames;
          ${publicIp} = publicNames;
        };
      };
    };

  den.aspects.media-stack = {
    includes =
      with den.aspects.nixos-services._;
      [
        arr
        jellyfin
        matrizApi
      ]
      ++ [
        den.aspects.service-host
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
