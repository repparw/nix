{
  lib,
  osConfig,
  ...
}:
let
  cloudDir = "/home/repparw/.cloud";
in
{
  config = lib.mkIf osConfig.modules.timers.enable {
    programs.rclone = {
      enable = true;
      remotes = {
        gdrive = {
          config = {
            type = "drive";
            scope = "drive";
          };
          secrets = {
            client_id = osConfig.age.secrets.rcloneDriveId.path;
            client_secret = osConfig.age.secrets.rcloneDriveSecret.path;
            token = osConfig.age.secrets.rcloneDriveToken.path;
          };
          mounts.gdrive = {
            enable = true;
            mountPoint = "${cloudDir}/gdrive";
            options = {
              exclude = "crypt/";
            };
          };
        };

        nextcloud = {
          config = {
            type = "webdav";
            url = "https://leo.it.tab.digital/remote.php/dav/files/ubritos%40gmail.com";
            vendor = "nextcloud";
            user = "ubritos@gmail.com";
          };
          secrets.pass = osConfig.age.secrets.rcloneNextcloud.path;
        };

        cryptunion = {
          config = {
            type = "union";
            upstreams = "gdrive:crypt nextcloud:crypt";
            policy_read = "all";
            action_policy = "all";
            create_policy = "all";
            search_policy = "all";
            cache_policy = "newest";
          };
        };

        crypt = {
          config = {
            type = "crypt";
            remote = "cryptunion:";
          };
          secrets = {
            password = osConfig.age.secrets.rcloneCrypt.path;
          };
          mounts.crypt = {
            enable = true;
            mountPoint = "${cloudDir}/crypt";
          };
        };

        dropbox = {
          config.type = "dropbox";
          secrets.token = osConfig.age.secrets.rcloneDropbox.path;
          mounts.dropbox = {
            enable = true;
            mountPoint = "${cloudDir}/dropbox";
          };
        };
      };
    };
  };
}
