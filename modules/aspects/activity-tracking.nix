{ den, ... }:
{
  den.aspects.activity-tracking = {
    homeManager =
      {
        config,
        lib,
        pkgs,
        osConfig,
        ...
      }:
      let
        syncDir = "${config.xdg.dataHome}/activitywatch/sync-outbox";
        remote = "${config.home.username}@${osConfig.modules.services.hostSshAddresses.epsilon}";
        sync = pkgs.writeShellApplication {
          name = "activitywatch-sync";
          runtimeInputs = [
            pkgs.openssh
            pkgs.rsync
          ];
          text = ''
            umask 077
            mkdir -p ${lib.escapeShellArg syncDir}
            # The basic 0.13 sync command omits browser buckets.
            ${pkgs.aw-server-rust}/bin/aw-sync --sync-dir ${lib.escapeShellArg syncDir} sync-advanced --mode push
            export RSYNC_RSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15"
            rsync -rt --chmod=D700,F600 --mkpath ${lib.escapeShellArg (syncDir + "/")} ${lib.escapeShellArg (remote + ":.local/share/activitywatch/sync-alpha/")}
            ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15 ${lib.escapeShellArg remote} activitywatch-import-alpha
          '';
        };
      in
      {
        services.activitywatch = {
          enable = true;
          package = pkgs.aw-server-rust;
          extraOptions = [
            "--host"
            "127.0.0.1"
          ];
        };

        # The Wayland watcher supplies both window and AFK buckets.
        systemd.user.services.activitywatch-wayland = {
          Unit = {
            Description = "ActivityWatch Wayland window and idle watcher";
            After = [ "activitywatch.service" ];
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

        # Keep the authoritative desktop database local. Retry transfers
        # periodically; no network connection is required for collection.
        systemd.user.services.activitywatch-sync = {
          Unit = {
            Description = "Sync desktop ActivityWatch data to Epsilon";
            After = [ "activitywatch.service" ];
            Wants = [ "activitywatch.service" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe sync;
            UMask = "0077";
            TimeoutStartSec = "10min";
          };
        };
        systemd.user.timers.activitywatch-sync = {
          Timer = {
            OnStartupSec = "5min";
            OnUnitInactiveSec = "15min";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };

    provides.server.nixos =
      { lib, pkgs, ... }:
      {
        # Private UI/API: access with SSH port forwarding, never public ingress.
        environment.systemPackages = [
          pkgs.rsync
          (pkgs.writeShellApplication {
            name = "activitywatch-import-alpha";
            runtimeInputs = [ pkgs.util-linux ];
            text = ''
              umask 077
              sync_dir="$HOME/.local/share/activitywatch/sync-alpha"
              exec flock "$sync_dir/.import.lock" ${pkgs.aw-server-rust}/bin/aw-sync --sync-dir "$sync_dir" sync-advanced --mode pull
            '';
          })
        ];

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
