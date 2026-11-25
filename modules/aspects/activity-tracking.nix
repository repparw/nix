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
        hostName = osConfig.networking.hostName;
        awDataDir = "${config.xdg.dataHome}/activitywatch";
        syncDir = "${awDataDir}/sync-outbox";
        lockFile = "${awDataDir}/.sync-outbox.lock";
        remote = "${config.home.username}@${osConfig.modules.services.hostSshAddresses.epsilon}";
        remoteStaging = "${remote}:.local/share/activitywatch/sync-${hostName}.staging/";
        sync = pkgs.writeShellApplication {
          name = "activitywatch-sync";
          runtimeInputs = [
            pkgs.openssh
            pkgs.rsync
            pkgs.util-linux
          ];
          text = ''
            umask 077
            mkdir -p ${lib.escapeShellArg syncDir}
            exec 9>${lib.escapeShellArg lockFile}
            flock 9
            # The basic 0.13 sync command omits browser buckets.
            ${pkgs.aw-server-rust}/bin/aw-sync --sync-dir ${lib.escapeShellArg syncDir} sync-advanced --mode push
            export RSYNC_RSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15"
            rsync -rt --delete --chmod=D700,F600 --mkpath ${lib.escapeShellArg (syncDir + "/")} ${lib.escapeShellArg remoteStaging}
            ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15 ${lib.escapeShellArg remote} activitywatch-import ${lib.escapeShellArg hostName}
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
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
            StartLimitIntervalSec = 0;
          };
          Service = {
            ExecStart = lib.getExe pkgs.aw-watcher-window-wayland;
            Restart = "on-failure";
            RestartSec = 5;
            UMask = "0077";
            LockPersonality = true;
            NoNewPrivileges = true;
            RestrictNamespaces = true;
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
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        homeDir = config.users.users.repparw.home;
      in
      {
        # Private UI/API: access with SSH port forwarding, never public ingress.
        environment.systemPackages = [
          pkgs.rsync
          (pkgs.writeShellApplication {
            name = "activitywatch-import";
            runtimeInputs = [
              pkgs.rsync
              pkgs.util-linux
            ];
            text = ''
              umask 077
              host="''${1:-}"
              if [[ ! "$host" =~ ^[a-z0-9-]+$ ]]; then
                echo "activitywatch-import: invalid host name: $host" >&2
                exit 1
              fi
              base_dir="$HOME/.local/share/activitywatch"
              staging_dir="$base_dir/sync-$host.staging"
              sync_dir="$base_dir/sync-$host"
              mkdir -p "$staging_dir" "$sync_dir"
              exec 9>"$base_dir/.import-$host.lock"
              flock 9
              rsync -rt --delete "$staging_dir/" "$sync_dir/"
              ${pkgs.aw-server-rust}/bin/aw-sync --sync-dir "$sync_dir" sync-advanced --mode pull
            '';
          })
        ];

        systemd.services.activitywatch = {
          description = "Central ActivityWatch server";
          wantedBy = [ "multi-user.target" ];
          environment = {
            HOME = homeDir;
            XDG_DATA_HOME = "${homeDir}/.local/share";
            XDG_CONFIG_HOME = "${homeDir}/.config";
          };
          serviceConfig = {
            User = "repparw";
            ExecStart = "${lib.getExe pkgs.aw-server-rust} --host 127.0.0.1";
            Restart = "on-failure";
            UMask = "0077";
            LockPersonality = true;
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "full";
            RestrictNamespaces = true;
            CapabilityBoundingSet = "";
          };
        };
      };
  };
}
