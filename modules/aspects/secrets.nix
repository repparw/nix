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
        }
        // (lib.optionalAttrs (config.modules.timers.enable or false) {
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
        })
        // (lib.optionalAttrs (config.services.archisteamfarm.enable or false) {
          steamPassword = {
            owner = "archisteamfarm";
          };
        })
        // (lib.optionalAttrs (config.modules.services.enable or false) {
          freshrss = { };
          cloudflare = { };
          karakeep = { };
        });

        sops.templates."cfait-config.toml" = {
          content = ''
            url = "https://leo.it.tab.digital/remote.php/dav/"
            username = "ubritos@gmail.com"
            password = "${config.sops.placeholder.nextcloud}"
            default_calendar = "Personal"
            disabled_calendars = ["local://default"]
          '';
          owner = "repparw";
          path = "/home/repparw/.config/cfait/config.toml";
        };
      };
  };
}
