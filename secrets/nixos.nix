{
  lib,
  config,
  ...
}: {
  age.secrets =
    {
      accessTokens = {
        file = ../secrets/access-tokens.age;
        owner = "repparw";
      };
    }
    // (lib.mkIf config.modules.timers.enable {
      rcloneDrive = {
        file = ../../secrets/rclone-drive.age;
        owner = "repparw";
      };
      rcloneCrypt = {
        file = ../../secrets/rclone-crypt.age;
        owner = "repparw";
      };
      rcloneDropbox = {
        file = ../../secrets/rclone-dropbox.age;
        owner = "repparw";
      };
    });

  age.identityPaths = ["/home/repparw/.ssh/id_ed25519"];
}
