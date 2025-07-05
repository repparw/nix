{
  lib,
  pkgs,
  osConfig,
  ...
}:
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
        };

        crypt = {
          config = {
            type = "crypt";
            remote = "gdrive:crypt";
          };
          secrets = {
            password = osConfig.age.secrets.rcloneCrypt.path;
          };
        };

        nextcloud = {
          config = {
            type = "webdav";
            url = "https://leo.it.tab.digital/";
            vendor = "nextcloud";
            user = "ubritos@gmail.com";
          };
          secrets.pass = osConfig.age.secrets.rcloneNextcloud.path;
        };

        dropbox = {
          config.type = "dropbox";
          secrets.token = osConfig.age.secrets.rcloneDropbox.path;
        };
      };
    };

    systemd.user.services =
      let
        mkRcloneMount =
          name: extraConfig:
          let
            mountDir = "/home/repparw/.cloud/${name}";
            baseConfig = {
              Unit = {
                Description = "Service that mounts ${name} remote";
              };
              Install.WantedBy = [ "graphical-session.target" ];
              Service = {
                Type = "simple";
                ExecStartPre = "/run/current-system/sw/bin/mkdir -p ${mountDir}";
                ExecStart = "${pkgs.rclone}/bin/rclone mount --vfs-cache-mode full ${name}: ${mountDir}";
                ExecStop = "/run/current-system/sw/bin/fusermount -u ${mountDir}";
                Restart = "on-failure";
                RestartSec = "10s";
                Environment = [ "PATH=/run/wrappers/bin/:$PATH" ];
              };
            };
          in
          lib.recursiveUpdate baseConfig extraConfig;
      in
      {
        rclone-mount-gdrive = mkRcloneMount "gdrive" {
          Service.ExecStart = "${pkgs.rclone}/bin/rclone mount --vfs-cache-mode full --exclude crypt/ gdrive: /home/repparw/.cloud/gdrive";
        };
        rclone-mount-crypt = mkRcloneMount "crypt" { };
        rclone-mount-dropbox = mkRcloneMount "dropbox" { };
        rclone-mount-nextcloud = mkRcloneMount "nextcloud" { };
      };
  };
}
