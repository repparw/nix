{
  lib,
  config,
  inputs,
  ...
}: {
  imports = [
    inputs.agenix.nixosModules.default
  ];

  age = {
    secrets =
      {
        accessTokens = {
          file = ./access-tokens.age;
          owner = "repparw";
        };
      }
      // (lib.mkIf config.modules.timers.enable {
        rcloneDrive = {
          file = ./rclone-drive.age;
          owner = "repparw";
        };
        rcloneCrypt = {
          file = ./rclone-crypt.age;
          owner = "repparw";
        };
        rcloneDropbox = {
          file = ./rclone-dropbox.age;
          owner = "repparw";
        };
      });

    identityPaths = ["/home/repparw/.ssh/id_ed25519"];
  };
}
