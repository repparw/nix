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

  # Host systems and addresses come from Den.
  hostSystems = lib.concatMapAttrs (system: hosts: lib.mapAttrs (_: _: system) hosts) den.hosts;
  deployPkgs = lib.mapAttrs (system: _: mkDeployPkgs system) den.hosts;
  sshAddresses = lib.concatMapAttrs (
    _: hosts: lib.mapAttrs (_: host: host.lanAddress or host.serviceAddress) hosts
  ) den.hosts;

  # Derive the controller from the host that owns the deployment timer.
  controllerHosts = lib.filter (
    host: inputs.self.nixosConfigurations.${host}.config.systemd.services ? fleet-deploy
  ) (lib.attrNames sshAddresses);
  controllerHost =
    if builtins.length controllerHosts == 1 then
      builtins.head controllerHosts
    else
      throw "Expected exactly one host with fleet-deploy.service";
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
    assert lib.hasAttr controllerHost sshAddresses;
    let
      controllerConfig = inputs.self.nixosConfigurations.${controllerHost}.config;
      servicesLib = import ./_services/lib.nix { inherit lib pkgs; };
      # Keep the parser in the fleet updater's runtime closure across GC.
      packageEvent = pkgs.writeTextFile {
        name = "fleet-package-event";
        destination = "/bin/package-update-event.py";
        executable = true;
        text = builtins.readFile ./scripts/package-update-event.py;
      };
    in
    pkgs.writeShellApplication {
      name = "fleet-update";
      runtimeInputs = with pkgs; [
        coreutils
        curl
        deploy-rs
        nix
        gawk
        jq
        openssh
        python3
        packageEvent
        systemd
        util-linux
        (servicesLib.mkDiscordNotify pkgs controllerConfig.modules.services.discordChannelId)
      ];
      text =
        builtins.replaceStrings
          [
            "@FLEET_HOST_JSON@"
            "@PACKAGE_EVENT_SCRIPT@"
          ]
          [
            hostAddressJson
            "${packageEvent}/bin/package-update-event.py"
          ]
          (builtins.readFile ./scripts/fleet-update.sh);
    };

  # Archive the WIP flake to the controller, then run deploy-rs inside a
  # controller-owned transient service. The remote service retains flock
  # even if the initiating SSH connection is interrupted.
  mkLocalDeploy =
    pkgs: skipChecks:
    pkgs.writeShellApplication {
      name = if skipChecks then "deploy" else "deploy-rs-locked";
      runtimeInputs = with pkgs; [
        nix
        jq
        openssh
        coreutils
      ];
      text = ''
        controller=${lib.escapeShellArg sshAddresses.${controllerHost}}
        controller_system=${lib.escapeShellArg hostSystems.${controllerHost}}
        ssh_options=(-i /home/repparw/.ssh/id_ed25519
          -o BatchMode=yes -o IdentitiesOnly=yes
          -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10
          -o ServerAliveInterval=15 -o ServerAliveCountMax=3)

        # Transfer the exact local source and locked inputs to Pi first.
        # No fleet operation is locked during this potentially long copy.
        export NIX_SSHOPTS="''${ssh_options[*]}"
        source=$(nix flake archive --json --to "ssh-ng://root@$controller" . |
          jq -er '.path | select(test("^/nix/store/[a-z0-9]+-[^/]+$"))')

        targets=()
        for arg in "$@"; do
          case "$arg" in
            .) targets+=("$source") ;;
            .#*) targets+=("$source#''${arg#.#}") ;;
            *) targets+=("$arg") ;;
          esac
        done
        if [ "''${#targets[@]}" -eq 0 ]; then
          targets=("$source")
        fi
        ${lib.optionalString skipChecks "targets+=(--skip-checks)"}

        unit="fleet-worktree-deploy-$(date +%s%N)-$$"
        echo "Controller-owned deployment: $unit (logs: journalctl -u $unit)" >&2
        remote=(systemd-run --wait --collect --unit="$unit"
          --property=Type=exec --property=RuntimeMaxSec=360min
          flock -w 10800 /run/fleet-update.lock
          nix run "$source#packages.$controller_system.deploy-rs" --
          "''${targets[@]}")
        # OpenSSH joins arguments into a remote shell command. Quote each one
        # to preserve the flake paths and optional deploy-rs arguments.
        printf -v command '%q ' "''${remote[@]}"
        # shellcheck disable=SC2029
        ssh "''${ssh_options[@]}" "root@$controller" "$command" || {
          echo "Deployment may still be running on Pi; check journalctl -u $unit before retrying" >&2
          exit 1
        }
      '';
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
          default = deployBase.nodes.${controllerHost}.hostname;
          readOnly = true;
          description = "Address of the serialized fleet deployment controller";
        };
        targetAddresses = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          readOnly = true;
          description = "Deploy target addresses used by controller-side fleet automation";
        };
      };

      config = {
        modules.fleet-update.package = mkFleetUpdate pkgs;
        modules.fleet-update.targetAddresses = lib.mapAttrs (_: node: node.hostname) deployBase.nodes;
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
        program = lib.getExe (mkLocalDeploy pkgs false);
        meta.description = "Deploy a local tree with deploy-rs and the fleet lock";
      };
      apps.deploy = {
        type = "app";
        program = lib.getExe (mkLocalDeploy pkgs true);
        meta.description = "Deploy a verified local tree with the fleet lock, skipping repeated flake checks";
      };
      apps.fleet-update = {
        type = "app";
        program = lib.getExe (mkFleetUpdate pkgs);
        meta.description = "Deploy the NixOS fleet after successful CI";
      };
    };
}
