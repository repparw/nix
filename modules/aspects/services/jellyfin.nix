{
  den,
  lib,
  ...
}:
{
  den.aspects.nixos-services.provides.jellyfin = {
    nixos =
      { config, pkgs, ... }:
      let
        cfg = config.modules.services;
        backupJob = import ../../_services/backup-job.nix { inherit lib pkgs; };
        jellyfinBackupKeyFile = config.sops.secrets.jellyfinBackupKey.path;
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
      ({
        networking.hosts."192.168.0.18" = [
          "jellyfin.${cfg.domain}"
        ];

        fileSystems."${cfg.backupDir}/jellyfin" = {
          depends = [ "/" ];
          device = "${cfg.configDir}/jellyfin/data/backups";
          fsType = "none";
          options = [
            "bind"
            "ro"
            "nofail"
          ];
        };

        systemd.services."container@jellyfin".after = [ "home-containers-backup-jellyfin.mount" ];

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
            "/data" = {
              hostPath = cfg.mediaPortalDir;
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
      })
      // (backupJob {
        name = "jellyfin";
        description = "jellyfin backup via native API";
        backupDir = "${cfg.configDir}/jellyfin/data/backups";
        inherit createBackup;
        filePattern = "jellyfin-backup-*.zip";
      });
  };
}
