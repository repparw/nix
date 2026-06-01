{
  den,
  lib,
  ...
}:
{
  den.aspects.rclone = {
    includes = [ ];

    homeManager =
      {
        osConfig,
        config,
        lib,
        ...
      }:
      let
        nc = config.accounts.calendar.accounts.nextcloud.remote;
      in
      {
        # Fix: rclone-config service must remain active after exit for mount dependencies
        systemd.user.services.rclone-config.Service.RemainAfterExit = "yes";
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
                mountPoint = "/home/repparw/.cloud/gdrive";
                options = {
                  exclude = "crypt/";
                };
              };
            };

            nextcloud = {
              config = {
                type = "webdav";
                url = "${lib.removeSuffix "/" (lib.removeSuffix "calendars/${nc.userName}/" nc.url)}/files/${
                  lib.replaceStrings [ "@" ] [ "%40" ] nc.userName
                }";
                vendor = "nextcloud";
                user = nc.userName;
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
              secrets.password = osConfig.sops.secrets.rcloneCrypt.path;
              mounts."" = {
                enable = true;
                mountPoint = "/home/repparw/.cloud/crypt";
              };
            };

            dropbox = {
              config.type = "dropbox";
              secrets.token = osConfig.sops.secrets.rcloneDropbox.path;
              mounts."apps/koreader-local/" = {
                enable = true;
                mountPoint = "/home/repparw/.cloud/dropbox";
              };
            };
          };
        };
      };
  };
}
