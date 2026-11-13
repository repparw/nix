{
  den,
  inputs,
  lib,
  ...
}:
let
  mkDeployPkgs =
    system:
    let
      pkgs = import inputs.nixpkgs { inherit system; };
    in
    import inputs.nixpkgs {
      inherit system;
      overlays = [
        inputs.deploy-rs.overlays.default
        (_: prev: {
          deploy-rs = {
            deploy-rs = pkgs.deploy-rs;
            lib = prev.deploy-rs.lib;
          };
        })
      ];
    };

  # Host systems and addresses come from Den; deployment ordering is separate.
  hostSystems = lib.concatMapAttrs (system: hosts: lib.mapAttrs (_: _: system) hosts) den.hosts;
  deployPkgs = lib.mapAttrs (system: _: mkDeployPkgs system) den.hosts;
  sshAddresses = lib.concatMapAttrs (
    _: hosts: lib.mapAttrs (_: host: host.sshAddress or host.serviceAddress) hosts
  ) den.hosts;

  # Preserve the current safety order: edge, workstation, then Pi controller.
  # Changing fleet topology requires reviewing this order rather than silently
  # deploying an unreviewed host or skipping it.
  deployOrder = [
    "epsilon"
    "alpha"
    "pi"
  ];
  hostAddressJson = builtins.toJSON sshAddresses;

  deployNode = hostname: {
    inherit hostname;
    remoteBuild = true;
    profiles.system.user = "root";
  };

  deployBase = {
    autoRollback = true;
    activationTimeout = 300;
    confirmTimeout = 60;
    magicRollback = true;
    tempPath = "/run/deploy-rs";
    sshUser = "root";
    sshOpts = [
      "-i"
      "/home/repparw/.ssh/id_ed25519"
      "-o"
      "BatchMode=yes"
      "-o"
      "IdentitiesOnly=yes"
      "-o"
      "StrictHostKeyChecking=accept-new"
    ];
    nodes = lib.mapAttrs (_: deployNode) sshAddresses;
  };

  deploySchema = deployBase // {
    nodes = lib.mapAttrs (
      _nodeName: node:
      lib.recursiveUpdate node { profiles.system.path = "/nix/store/deploy-schema-placeholder"; }
    ) deployBase.nodes;
  };

  mkFleetUpdate =
    pkgs:
    assert lib.sort lib.lessThan (lib.attrNames sshAddresses) == lib.sort lib.lessThan deployOrder;
    let
      controllerConfig = inputs.self.nixosConfigurations.pi.config;
      servicesLib = import ./_services/lib.nix { inherit lib pkgs; };
      controllerServices = controllerConfig.modules.services;
      jellyfinService = controllerServices.definitions.jellyfin;
      jellyfinHealthUrl =
        if jellyfinService.healthcheck == null then
          throw "Jellyfin must have a registered healthcheck for fleet deployment"
        else
          "${servicesLib.serviceUrl controllerServices controllerConfig "jellyfin"}${jellyfinService.healthcheck}";
      # The event parser is a store path substituted into the script text. It
      # cannot be discovered next to the executable: writeShellApplication
      # embeds only this script, so a runtime search of the store bin
      # directory would find nothing.
      packageEvent = ./scripts/package-update-event.py;
    in
    pkgs.writeShellApplication {
      name = "fleet-update";
      runtimeInputs = with pkgs; [
        coreutils
        curl
        deploy-rs
        git
        gawk
        jq
        nix
        openssh
        python3
        systemd
        util-linux
        (servicesLib.mkDiscordNotify pkgs controllerConfig.modules.services.discordChannelId)
      ];
      text =
        builtins.replaceStrings
          [
            "@FLEET_JELLYFIN_HOST@"
            "@FLEET_JELLYFIN_HEALTH_URL@"
            "@FLEET_HOST_JSON@"
            "@FLEET_HOST_OPTIONS@"
            "@FLEET_DEPLOY_ORDER@"
            "@FLEET_ROLLBACK_ORDER@"
            "@FLEET_DOMAIN@"
            "@FLEET_DISCORD_CHANNEL@"
            "@PACKAGE_EVENT_SCRIPT@"
          ]
          [
            jellyfinService.host
            jellyfinHealthUrl
            hostAddressJson
            (lib.concatStringsSep "|" (lib.attrNames sshAddresses))
            (lib.concatStringsSep " " deployOrder)
            (lib.concatStringsSep " " (lib.reverseList deployOrder))
            controllerConfig.modules.services.domain
            controllerConfig.modules.services.discordChannelId
            (toString packageEvent)
          ]
          (builtins.readFile ./scripts/fleet-update.sh);
    };

  mkDeploySchemaCheck =
    pkgs:
    pkgs.runCommand "deploy-schema" { nativeBuildInputs = [ pkgs.check-jsonschema ]; } ''
      check-jsonschema \
        --schemafile ${inputs.deploy-rs}/interface.json \
        ${pkgs.writeText "deploy.json" (
          builtins.unsafeDiscardStringContext (builtins.toJSON deploySchema)
        )}
      touch "$out"
    '';

  mkActivationCheck =
    pkgs: node:
    let
      profile = inputs.self.deploy.nodes.${node}.profiles.system.path;
    in
    pkgs.runCommand "deploy-activate-${node}" { } ''
      test -f ${profile}/deploy-rs-activate
      test -f ${profile}/activate-rs
      touch "$out"
    '';
in
{
  flake-file.inputs.deploy-rs = {
    url = "github:serokell/deploy-rs";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.deploy-target.nixos =
    { config, pkgs, ... }:
    {
      options.modules.fleet-update = {
        package = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "Transactional deploy-rs fleet updater";
        };
        controllerHost = lib.mkOption {
          type = lib.types.str;
          default = deployBase.nodes.pi.hostname;
          readOnly = true;
          description = "Address of the serialized fleet deployment controller";
        };
        targetAddresses = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          readOnly = true;
          description = "Deploy target addresses used by controller-side fleet automation";
        };
        containerUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          readOnly = true;
          description = ''
            Container units owned by this host, derived from service
            definitions with container = true. Fleet health gates eval this
            per target so the checked unit list cannot drift from the
            registry when services move between hosts.
          '';
        };
      };

      config = {
        modules.fleet-update.package = mkFleetUpdate pkgs;
        modules.fleet-update.targetAddresses = lib.mapAttrs (_: node: node.hostname) deployBase.nodes;
        modules.fleet-update.containerUnits = map (name: "container@${name}") (
          lib.attrNames (
            lib.filterAttrs (_: service: service.host == config.networking.hostName && service.container) (
              config.modules.services.definitions or { }
            )
          )
        );
        systemd.tmpfiles.rules = [ "d /run/deploy-rs 0700 root root -" ];
        users.users.root.openssh.authorizedKeys.keys =
          config.users.users.repparw.openssh.authorizedKeys.keys;
        system.configurationRevision = inputs.self.rev or (inputs.self.dirtyRev or null);
      };
    };

  flake.deploy = lib.recursiveUpdate deployBase {
    nodes = lib.mapAttrs (hostname: system: {
      profiles.system.path =
        deployPkgs.${system}.deploy-rs.lib.activate.nixos
          inputs.self.nixosConfigurations.${hostname};
    }) hostSystems;
  };

  flake.checks = lib.mapAttrs (
    system: hosts:
    {
      deploy-schema = mkDeploySchemaCheck deployPkgs.${system};
    }
    // lib.mapAttrs' (
      hostname: _:
      lib.nameValuePair "deploy-activate-${hostname}" (mkActivationCheck deployPkgs.${system} hostname)
    ) hosts
  ) den.hosts;

  perSystem =
    { pkgs, ... }:
    {
      packages.deploy-rs = pkgs.deploy-rs;
      packages.fleet-update = mkFleetUpdate pkgs;

      apps.deploy-rs = {
        type = "app";
        program = lib.getExe pkgs.deploy-rs;
        meta.description = "Deploy a configured node with deploy-rs";
      };
      apps.deploy = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "deploy";
            text = ''
              exec ${lib.getExe pkgs.deploy-rs} "$@" --skip-checks
            '';
          }
        );
        meta.description = "Deploy a verified local tree without repeating flake checks";
      };
      apps.fleet-update = {
        type = "app";
        program = lib.getExe (mkFleetUpdate pkgs);
        meta.description = "Deploy the NixOS fleet after successful CI";
      };
    };
}
