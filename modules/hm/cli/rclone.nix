{
  lib,
  osConfig,
  ...
}: {
  config = lib.mkIf osConfig.modules.timers.enable {
    programs.rclone = {
      enable = true;
      remotes = {
        drive = {
          config = {
            type = "drive";
            scope = "drive";
          };
          secrets = {
            client_id = osConfig.age.secrets.rcloneDriveId.path;
            client_secret = osConfig.age.secrets.rcloneDriveSecret.path;
            token = osConfig.age.secrets.rcloneDriveToken.path;
          };
        };

        crypt = {
          config = {
            type = "crypt";
            remote = "drive:crypt";
          };
          secrets = {
            password = osConfig.age.secrets.rcloneCrypt.path;
          };
        };
        dropbox = {
          config.type = "dropbox";
          secrets.token = osConfig.age.secrets.rcloneDropbox.path;
        };
      };
    };
  };
}
