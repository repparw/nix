{
  den,
  inputs,
  lib,
  ...
}:
let
  # Keep deploy-rs' activation library, but use the cache-backed Nixpkgs CLI
  # in generated activation wrappers.
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

  deployBase = {
    autoRollback = true;
    activationTimeout = 180;
    confirmTimeout = 90;
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
    nodes = {
      epsilon = {
        hostname = "146.181.42.97";
        remoteBuild = true;
        profiles.system.user = "root";
      };
      pi = {
        hostname = "192.168.0.4";
        remoteBuild = true;
        profiles.system.user = "root";
      };
      alpha = {
        hostname = "192.168.0.18";
        remoteBuild = true;
        profiles.system.user = "root";
      };
    };
  };

  deploySchema = deployBase // {
    nodes = lib.mapAttrs (
      _nodeName: node:
      lib.recursiveUpdate node { profiles.system.path = "/nix/store/deploy-schema-placeholder"; }
    ) deployBase.nodes;
  };

  mkFleetUpdate =
    pkgs:
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
          ]
          [
            deployBase.nodes.alpha.hostname
            deployBase.nodes.pi.hostname
            deployBase.nodes.epsilon.hostname
          ]
          (builtins.readFile ./scripts/fleet-update.sh);
    };

  mkDeploySchemaCheck =
    pkgs:
    # The interface only requires profile paths to be strings. The
    # architecture-neutral base avoids evaluating every system closure (and
    # any IFD it contains) on the runner. Native checks validate real paths.
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

  # Shared target plumbing. Key-only root access lets the always-on pi
  # controller activate every node without password-bearing automation.
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
      };

      config = {
        modules.fleet-update.package = mkFleetUpdate pkgs;
        systemd.tmpfiles.rules = [ "d /run/deploy-rs 0700 root root -" ];
        users.users.root.openssh.authorizedKeys.keys = import ../authorized-keys.nix;
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

  # Schema checks discard store-path contexts and therefore validate the
  # mixed-architecture graph on either runner. Activation checks stay native.
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
