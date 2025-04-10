{
  osConfig,
  pkgs,
  lib,
  ...
}: let
  git-autocommit = with pkgs;
    writeShellApplication {
      name = "git-autocommit";
      runtimeInputs = [gitMinimal];
      text = ''
        DIR=''${1:-/home/repparw/nix}
        git -C "$DIR" add -A
        git -C "$DIR" commit -m "Autocommit"
        git -C "$DIR" pull --rebase
        git -C "$DIR" push
      '';
    };
in {
  services.spotifyd.enable = true;

  modules.jellyfin-mpv-shim.enable = true;

  #home.packages = with pkgs; [ ];

  systemd.user.services.git-autocommit = {
    Service = {
      Type = "oneshot";
      ExecStart = ["${lib.getExe git-autocommit}"];
    };
  };

  systemd.user.timers.git-autocommit = {
    Install = {
      WantedBy = ["timers.target"];
    };
    Timer = {
      OnCalendar = "*:0/4";
      Persistent = true;
    };
  };

  config = lib.mkIf osConfig.modules.timers.enable {
    age.secrets = {
      rcloneDrive = {
        file = ../secrets/rclone-drive.age;
      };
      rcloneCrypt = {
        file = ../secrets/rclone-crypt.age;
      };
      rcloneDropbox = {
        file = ../secrets/rclone-dropbox.age;
      };
    };

    programs.rclone = {
      enable = true;
      remotes = {
        drive = {
          config = {
            type = "drive";
            scope = "drive";
            client_id = "333265659347-c03ga8iml374j79nod16pb79kkfkel7f.apps.googleusercontent.com";
          };
          secrets = {
            client_secret = osConfig.age.secrets.rcloneDrive.path;
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
