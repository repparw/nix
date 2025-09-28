{
  lib,
  config,
  inputs,
  ...
}:
{
  imports = [
    inputs.agenix.nixosModules.default
  ];

  age = {
    secrets = {
      accessTokens = {
        file = ./access-tokens.age;
        mode = "0440";
        owner = "repparw";
      };
      nextcloud = {
        file = ./nextcloud.age;
        owner = "repparw";
      };
    }
    // (lib.optionalAttrs config.modules.timers.enable {
      rcloneDriveToken = {
        file = ./services/rclone/drive-token.age;
        owner = "repparw";
      };
      rcloneDriveId = {
        file = ./services/rclone/drive-id.age;
        owner = "repparw";
      };
      rcloneDriveSecret = {
        file = ./services/rclone/drive-secret.age;
        owner = "repparw";
      };
      rcloneCrypt = {
        file = ./services/rclone/crypt.age;
        owner = "repparw";
      };
      rcloneDropbox = {
        file = ./services/rclone/dropbox.age;
        owner = "repparw";
      };
      rcloneNextcloud = {
        file = ./services/rclone/nextcloud.age;
        owner = "repparw";
      };
    })
    // (lib.optionalAttrs config.services.archisteamfarm.enable {
      steamPassword = {
        file = ./steam-password.age;
        owner = "repparw";
      };
    })
    // (lib.optionalAttrs config.modules.services.enable {
      freshrss.file = ./services/freshrss.age;
      cloudflare.file = ./services/proxy/cloudflare.age;
    });

    identityPaths = [ "/home/repparw/.ssh/id_ed25519" ];
  };
}
