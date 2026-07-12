{
  inputs,
  lib,
  ...
}:
{
  flake-file.inputs.sops-nix = {
    url = "github:Mic92/sops-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.secrets = {
    nixos =
      { config, pkgs, ... }:
      let
        user = config.users.users.repparw;
        userHome = user.home;
      in
      {
        imports = [
          inputs.sops-nix.nixosModules.sops
        ];

        environment.systemPackages = [
          inputs.sops-nix.packages.${pkgs.stdenv.hostPlatform.system}.sops-import-keys-hook
        ];

        sops = {
          defaultSopsFile = ../../secrets.yaml;
          defaultSopsFormat = "yaml";
        };

        sops.age.sshKeyPaths = [ "${userHome}/.ssh/id_ed25519" ];

      };
  };
}
