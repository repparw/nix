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
        tod0 = {
          file = ./tod0.age;
          owner = "repparw";
          group = "users";
          path = "${config.home-manager.users.repparw.xdg.configHome}/tod0/keys.yml";
          mode = "600";
        };
      }
      // (lib.optionalAttrs config.modules.timers.enable {
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
