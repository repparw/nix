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

  deployPkgs = {
    aarch64-linux = mkDeployPkgs "aarch64-linux";
    x86_64-linux = mkDeployPkgs "x86_64-linux";
  };

  sshAddresses = lib.mapAttrs (_: host: host.sshAddress or host.serviceAddress) (
    lib.concatMapAttrs (_system: hosts: hosts) den.hosts
  );

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
    let
      # Fleet facts as the controller evaluates them. service-definitions.nix
      # (imported by service-host on every fleet host) is the canonical source;
      # pi is the serialized fleet controller (deployBase.nodes below), so its
      # config resolves the option defaults the script is built from. Lazy
      # read: the fixed-point materializes before the package value is forced.
      controllerConfig = inputs.self.nixosConfigurations.pi.config;
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
        systemd
        util-linux
      ];
      text =
        builtins.replaceStrings
          [
            "@FLEET_ALPHA_ADDRESS@"
            "@FLEET_PI_ADDRESS@"
            "@FLEET_EPSILON_ADDRESS@"
            "@FLEET_DOMAIN@"
            "@FLEET_DISCORD_CHANNEL@"
          ]
          [
            deployBase.nodes.alpha.hostname
            deployBase.nodes.pi.hostname
            deployBase.nodes.epsilon.hostname
            controllerConfig.modules.services.domain
            controllerConfig.modules.services.discordChannelId
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
        activityGate = lib.mkOption {
          type = lib.types.bool;
          default = config.modules.desktop.enable or false;
          readOnly = true;
          description = "Whether deployment waits for local graphical sessions to be idle or locked";
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
        # Definitions come from the fleet-wide service registry (every host
        # sees all services with their owning host); the empty fallback
        # keeps a service-less deploy target evaluable.
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
    nodes = {
      epsilon.profiles.system.path = deployPkgs.aarch64-linux.deploy-rs.lib.activate.nixos inputs.self.nixosConfigurations.epsilon;
      pi.profiles.system.path = deployPkgs.aarch64-linux.deploy-rs.lib.activate.nixos inputs.self.nixosConfigurations.pi;
      alpha.profiles.system.path = deployPkgs.x86_64-linux.deploy-rs.lib.activate.nixos inputs.self.nixosConfigurations.alpha;
    };
  };

  flake.checks = {
    aarch64-linux = {
      deploy-schema = mkDeploySchemaCheck deployPkgs.aarch64-linux;
      deploy-activate-epsilon = mkActivationCheck deployPkgs.aarch64-linux "epsilon";
      deploy-activate-pi = mkActivationCheck deployPkgs.aarch64-linux "pi";
    };
    x86_64-linux = {
      deploy-schema = mkDeploySchemaCheck deployPkgs.x86_64-linux;
      deploy-activate-alpha = mkActivationCheck deployPkgs.x86_64-linux "alpha";
    };
  };

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
      apps.fleet-update = {
        type = "app";
        program = lib.getExe (mkFleetUpdate pkgs);
        meta.description = "Promote or deploy the NixOS fleet transactionally";
      };
    };
}
