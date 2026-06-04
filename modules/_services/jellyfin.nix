{
  cfg,
  config,
  pkgs,
  lib,
  ...
}:
let
  jellyfinBackupKeyFile = config.sops.secrets.jellyfinBackupKey.path;
  pruneBackups = pkgs.writeShellApplication {
    name = "jellyfin-prune-backups";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail
      cd "${cfg.configDir}/jellyfin/data/backups"
      # keep newest 7, delete the rest
      ls -1t jellyfin-backup-*.zip 2>/dev/null | tail -n +8 | xargs -r rm -v
    '';
  };
  createBackup = pkgs.writeShellApplication {
    name = "jellyfin-create-backup";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      set -euo pipefail
      key=$(cat ${jellyfinBackupKeyFile})
      response=$(curl -fsS -X POST \
        -H "X-Emby-Token: $key" \
        -H "Content-Type: application/json" \
        -d '{}' \
        http://10.231.136.10:8096/Backup/Create)
      echo "$response"
      path=$(echo "$response" | sed -n 's/.*"Path":"\([^"]*\)".*/\1/p')
      if [ -n "$path" ]; then
        echo "backup created: $path"
      else
        echo "warning: could not parse backup path from response" >&2
      fi
    '';
  };
in
{
  containers.jellyfin = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.10";
    bindMounts = {
      "/var/lib/jellyfin" = {
        hostPath = "${cfg.configDir}/jellyfin";
        isReadOnly = false;
      };
      "/data/media" = {
        hostPath = "${cfg.dataDir}/media";
        isReadOnly = false;
      };
      "/seagate" = {
        hostPath = cfg.externalDataDir;
        isReadOnly = false;
      };
    };
    allowedDevices = [
      {
        node = "/dev/dri/renderD128";
        modifier = "rwm";
      }
      {
        node = "/dev/dri/card0";
        modifier = "rwm";
      }
    ];
    config =
      { ... }:
      {
        networking.useHostResolvConf = false;
        networking.nameservers = [ "10.231.136.1" ];

        services.jellyfin = {
          enable = true;
          openFirewall = true;
        };

        hardware.graphics = {
          enable = true;
          extraPackages = with pkgs; [
            libva-vdpau-driver
            libvdpau-va-gl
            intel-media-driver
          ];
        };

        users.users.jellyfin.extraGroups = [
          "video"
          "render"
        ];

        system.stateVersion = "26.05";
      };
  };

  systemd.services.jellyfin-backup = {
    description = "Create jellyfin backup via native API";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe createBackup;
      ExecStartPost = lib.getExe pruneBackups;
    };
    wantedBy = [ ];
  };
  systemd.timers.jellyfin-backup = {
    description = "Run jellyfin backup daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };
}
