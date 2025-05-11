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
            token = osConfig.age.secrets.rcloneDrive.path;
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
