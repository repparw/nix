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
          rcloneClarodrive = {
            owner = "repparw";
          };
          resticPassword = {
            owner = "repparw";
          };
          cloudflare = {
            owner = "repparw";
          };
          qbittorrentAuth = {
            owner = "traefik";
            group = "traefik";
            mode = "0400";
          };
          jellyfinBackupKey = {
            owner = "root";
            mode = "0400";
          };
          ddclientPassword = {
            owner = "ddclient";
            group = "ddclient";
            mode = "0400";
          };
          "authelia/jwtSecret" = {
            owner = "root";
            mode = "0400";
          };
          "authelia/oidcHmacSecret" = {
            owner = "root";
            mode = "0400";
          };
          "authelia/oidcJwksKey" = {
            owner = "root";
            mode = "0400";
          };
          "authelia/sessionSecret" = {
            owner = "root";
            mode = "0400";
          };
          "authelia/smtpPassword" = {
            owner = "root";
            mode = "0400";
          };
          "authelia/storageEncryptionKey" = {
            owner = "root";
            mode = "0400";
          };
          steamPassword = {
            owner = "root";
            mode = "0400";
          };
        };

      };
  };
}
