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
        servicesLib = import ../../_services/lib.nix { inherit lib pkgs; };
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
              http://${cfg.inventory.jellyfin.containerAddress}:${toString cfg.inventory.jellyfin.port}/Backup/Create)
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
        sops.secrets.jellyfinBackupKey = {
          owner = "root";
          mode = "0400";
        };

        modules.services.inventory.jellyfin = {
          hostname = "jellyfin";
          containerAddress = "10.231.136.10";
          port = 8096;
          auth = "bypass";
          backup.path = "${cfg.configDir}/jellyfin/data/backups";
          monitor = true;
        };

        containers.jellyfin = servicesLib.mkContainer {
          inherit cfg;
          name = "jellyfin";
          privateUsers = "pick";
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
            {
              # DRM card numbering can shift across boots/kernel updates.
              node = "/dev/dri/card1";
              modifier = "rwm";
            }
          ];
          extraConfig = {
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
          };
        };

        systemd.services."container@jellyfin".serviceConfig = {
          CPUQuota = "300%";
          IOWeight = 50;
          Nice = 10;
        };
      })
      // (servicesLib.mkBackupJob {
        name = "jellyfin";
        description = "jellyfin backup via native API";
        backupDir = "${cfg.configDir}/jellyfin/data/backups";
        inherit createBackup;
        filePattern = "jellyfin-backup-*.zip";
      });
  };
}
