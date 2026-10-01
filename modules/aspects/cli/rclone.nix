{
  den,
  lib,
  ...
}:
{
  den.aspects.rclone = {
    nixos = { config, ... }: {
      sops.secrets = builtins.listToAttrs (
        map
          (name: {
            inherit name;
            value = {
              sopsFile = ../../../secrets/rclone.sops.yaml;
              owner = config.users.users.repparw.name;
            };
          })
          [
            "rcloneDriveToken"
            "rcloneDriveId"
            "rcloneDriveSecret"
            "rcloneCrypt"
            "rcloneDropbox"
            "rcloneNextcloud"
            "rcloneClarodrive"
            "rcloneClarodriveUser"
            "rcloneClarodriveUrl"
          ]
      );
    };

    homeManager =
      {
        osConfig,
        config,
        lib,
        ...
      }:
      let
        cloudDir = "${config.home.homeDirectory}/.cloud";
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
                upstreams = "gdrive:crypt nextcloud:crypt claro:crypt";
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
                mountPoint = "${cloudDir}/crypt";
              };
            };

            gd-crypt = {
              config = {
                type = "crypt";
                remote = "gdrive:";
              };
              secrets.password = osConfig.sops.secrets.rcloneCrypt.path;
            };

            dropbox = {
              config.type = "dropbox";
              secrets.token = osConfig.sops.secrets.rcloneDropbox.path;
              mounts."apps/koreader-local/" = {
                enable = true;
                mountPoint = "${cloudDir}/dropbox";
              };
            };

            claro = {
              config = {
                type = "webdav";
                vendor = "nextcloud";
              };
              secrets = {
                url = osConfig.sops.secrets.rcloneClarodriveUrl.path;
                user = osConfig.sops.secrets.rcloneClarodriveUser.path;
                pass = osConfig.sops.secrets.rcloneClarodrive.path;
              };
              mounts."" = {
                enable = true;
                mountPoint = "${cloudDir}/claro";
              };
            };
          };
        };
      };
  };
}
