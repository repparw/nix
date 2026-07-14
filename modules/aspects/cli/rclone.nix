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
        clarodriveUser = "f8ff72993b43109297c1f4e7";
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
                url = "https://i0001.clarodrive.com/remote.php/dav/files/${clarodriveUser}";
                vendor = "nextcloud";
                user = clarodriveUser;
              };
              secrets.pass = osConfig.sops.secrets.rcloneClarodrive.path;
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
