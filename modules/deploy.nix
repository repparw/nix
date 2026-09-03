{
  inputs,
  lib,
  ...
}:
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
      path = inputs.deploy-rs.lib.aarch64-linux.activate.nixos inputs.self.nixosConfigurations.epsilon;
    };
  };
}
