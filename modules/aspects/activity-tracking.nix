{ den, ... }:
{
  den.aspects.activity-tracking = {
    homeManager = { lib, pkgs, ... }: {
      services.activitywatch = {
        enable = true;
        package = pkgs.aw-server-rust;
        extraOptions = [
          "--host"
          "127.0.0.1"
        ];
      };

      # Start the Wayland watcher only once the graphical session has its
      # compositor environment. It supplies both window and AFK buckets.
      systemd.user.services.activitywatch-wayland = {
        Unit = {
          Description = "ActivityWatch Wayland window and idle watcher";
          After = [
            "graphical-session.target"
            "activitywatch.service"
          ];
          Wants = [ "activitywatch.service" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = lib.getExe pkgs.aw-watcher-window-wayland;
          Restart = "on-failure";
          RestartSec = 5;
          UMask = "0077";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      systemd.user.services.activitywatch.Service.UMask = "0077";
    };

    provides.server.nixos = { lib, pkgs, ... }: {
      # Keep the central UI and API private. Access with SSH port forwarding.
      # Sync transport is separate and must not expose the raw HTTP API.
      systemd.services.activitywatch = {
        description = "Central ActivityWatch server";
        wantedBy = [ "multi-user.target" ];
        environment = {
          HOME = "/home/repparw";
          XDG_DATA_HOME = "/home/repparw/.local/share";
          XDG_CONFIG_HOME = "/home/repparw/.config";
        };
        serviceConfig = {
          User = "repparw";
          ExecStart = "${lib.getExe pkgs.aw-server-rust} --host 127.0.0.1";
          Restart = "on-failure";
          UMask = "0077";
          NoNewPrivileges = true;
        };
      };
    };
  };
}
