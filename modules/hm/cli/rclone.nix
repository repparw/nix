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
            client_id = osConfig.sops.secrets.rcloneDriveId.path;
            client_secret = osConfig.sops.secrets.rcloneDriveSecret.path;
            token = osConfig.sops.secrets.rcloneDriveToken.path;
          };
          mounts."" = {
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
          secrets.pass = osConfig.sops.secrets.rcloneNextcloud.path;
        };

        union = {
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
            remote = "union:";
          };
          secrets = {
            password = osConfig.sops.secrets.rcloneCrypt.path;
          };
          mounts."" = {
            enable = true;
            mountPoint = "${cloudDir}/crypt";
          };
        };

        dropbox = {
          config.type = "dropbox";
          secrets.token = osConfig.sops.secrets.rcloneDropbox.path;
          mounts."" = {
            enable = true;
            mountPoint = "${cloudDir}/dropbox";
          };
        };
      };
    };
  };
}
