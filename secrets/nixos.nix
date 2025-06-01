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
    secrets =
      {
        accessTokens = {
          file = ./access-tokens.age;
          mode = "0440";
          owner = "repparw";
        };
        tod0 = {
          file = ./tod0.age;
          owner = "repparw";
          group = "users";
          path = "${config.home-manager.users.repparw.xdg.configHome}/tod0/keys.yml";
          mode = "600";
        };
      }
      // (lib.optionalAttrs config.modules.timers.enable {
        rcloneDriveToken = {
          file = ./rclone/drive-token.age;
          owner = "repparw";
        };
        rcloneDriveId = {
          file = ./rclone/drive-id.age;
          owner = "repparw";
        };
        rcloneDriveSecret = {
          file = ./rclone/drive-secret.age;
          owner = "repparw";
        };
        rcloneCrypt = {
          file = ./rclone/crypt.age;
          owner = "repparw";
        };
        rcloneDropbox = {
          file = ./rclone/dropbox.age;
          owner = "repparw";
        };
      });

    identityPaths = [ "/home/repparw/.ssh/id_ed25519" ];
  };
}
