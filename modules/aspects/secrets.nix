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

        sops.age.sshKeyPaths = [ "/home/repparw/.ssh/id_ed25519" ];

        sops.secrets = {
          accessTokens = {
            mode = "0440";
            owner = "repparw";
          };
          nextcloud = {
            owner = "repparw";
          };
          rcloneDriveToken = {
            owner = "repparw";
          };
          rcloneDriveId = {
            owner = "repparw";
          };
          rcloneDriveSecret = {
            owner = "repparw";
          };
          rcloneCrypt = {
            owner = "repparw";
          };
          rcloneDropbox = {
            owner = "repparw";
          };
          rcloneNextcloud = {
            owner = "repparw";
          };
          freshrss = {
            owner = "repparw";
          };
          cloudflare = {
            owner = "repparw";
          };
          karakeep = {
            owner = "repparw";
          };
          qbittorrentAuth = {
            owner = "repparw";
            mode = "0400";
          };
        }
        // (lib.optionalAttrs (config.services.archisteamfarm.enable or false) {
          steamPassword = {
            owner = "archisteamfarm";
          };
        });

      };
  };
}
