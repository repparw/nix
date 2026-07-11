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
        userName = user.name;
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

        sops.secrets = {
          accessTokens = {
            mode = "0440";
            owner = userName;
          };
          nextcloud = {
            owner = userName;
          };
          rcloneDriveToken = {
            owner = userName;
          };
          rcloneDriveId = {
            owner = userName;
          };
          rcloneDriveSecret = {
            owner = userName;
          };
          rcloneCrypt = {
            owner = userName;
          };
          rcloneDropbox = {
            owner = userName;
          };
          rcloneNextcloud = {
            owner = userName;
          };
          rcloneClarodrive = {
            owner = userName;
          };
          resticPassword = {
            owner = userName;
          };
          cloudflare = {
            owner = userName;
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
          discordWebhook = {
            owner = "root";
            mode = "0400";
          };
          sunshineApiUsername = {
            owner = userName;
            mode = "0400";
          };
          sunshineApiPassword = {
            owner = userName;
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
