{
  inputs,
  lib,
  ...
}:
let
  # Keep deploy-rs' activation library, but use the cache-backed Nixpkgs CLI
  # in the generated activation wrapper. This is the upstream-recommended
  # overlay shape and avoids rebuilding the Rust CLI for every target system.
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
  epsilonDeployPkgs = mkDeployPkgs "aarch64-linux";
  deployChecksFor = system: (mkDeployPkgs system).deploy-rs.lib.deployChecks inputs.self.deploy;
in
{
  # deploy-rs prototype: epsilon first (no pipeline there today). Deploys
  # run from alpha against origin/main — the same pin pi's pipeline
  # publishes — with the closure built on the target and deploy-rs'
  # auto-rollback + magic rollback covering boot-level failures.
  flake-file.inputs.deploy-rs = {
    url = "github:serokell/deploy-rs";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake.deploy.nodes.epsilon = {
    # ssh config alias; root has the shared authorized keys.
    hostname = "epsilon";
    sshUser = "root";
    remoteBuild = true;
    profiles.system = {
      user = "root";
      path = epsilonDeployPkgs.deploy-rs.lib.activate.nixos inputs.self.nixosConfigurations.epsilon;
    };
  };

  # Expose deploy-rs' graph and activation checks for manual remote
  # validation. Both retain references to epsilon's aarch64 closure, so they
  # run on epsilon (or another configured aarch64 builder), not the x86_64 CI
  # runner.
  flake.checks.aarch64-linux = deployChecksFor "aarch64-linux";

  # Use the cache-backed Nixpkgs CLI with deploy-rs' flake library. Building
  # the input's bundled CLI is unnecessary and bypasses the binary cache.
  perSystem =
    { pkgs, ... }:
    {
      packages.deploy-rs = pkgs.deploy-rs;
      apps.deploy-rs = {
        type = "app";
        program = lib.getExe pkgs.deploy-rs;
        meta.description = "Deploy a configured node with deploy-rs";
      };
    };
}
