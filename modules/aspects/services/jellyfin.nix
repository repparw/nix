{
  den,
  lib,
  ...
}:
{
  den.aspects.nixos-services.provides.jellyfin = {
    service-registry = {
      name = "jellyfin";
      definition = {
        hostname = "jellyfin";
        port = 8096;
        auth = "bypass";
        container = true;
        monitor = true;
        lanEdge = true;
        healthcheck = "/health";
        backupRelativePath = "jellyfin/data/backups";
      };
    };

    nixos =
      { config, pkgs, ... }:
      let
        cfg = config.modules.services;
        servicesLib = import ../../_services/lib.nix { inherit lib pkgs; };
        service = cfg.definitions.jellyfin;
        jellyfinBackupKeyFile = config.sops.secrets.jellyfinBackupKey.path;

        # Authelia authentication plugin (github.com/nikarh/jellyfin-plugin-authelia),
        # pinned to the release matching the server's plugin ABI. Logins keep the
        # native Jellyfin form and API; passwords are verified against Authelia's
        # HTTP API instead of the local hash. Bump the pin with the server's ABI:
        # the release manifest declares targetAbi per version.
        autheliaPluginRelease = pkgs.fetchzip {
          name = "jellyfin-plugin-authelia-authentication-1.0.17.0";
          url = "https://github.com/nikarh/jellyfin-plugin-authelia/releases/download/1.0.17/authelia-authentication_1.0.17.0.zip";
          sha256 = "sha256-n+e9cJYVeOjOS70agtAVhOo9Bo3tFRS5ww0+KfxWo/U=";
          stripRoot = false;
        };
        autheliaPluginLogo = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/nikarh/jellyfin-plugin-authelia/master/logo.png";
          sha256 = "sha256-s9ILReVI7jol/MWI5t1kG4i6caHp1Is7iVKbcD42kV4=";
        };
        # Keep the pinned plugin installed across server restarts. The plugin
        # manager owns the live tree, but this pin restores missing binaries.
        # The old account-provider migration is intentionally not repeated.
        seedAutheliaPlugin = pkgs.writeShellApplication {
          name = "jellyfin-authelia-seed";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            set -euo pipefail
            pluginDir='/var/lib/jellyfin/plugins/Authelia Authentication_1.0.17.0'
            db=/var/lib/jellyfin/data/jellyfin.db

            if [ ! -f "$pluginDir/Authelia-Auth.dll" ]; then
              echo "seeding Authelia Authentication 1.0.17.0 from the declarative source"
              mkdir -p "$pluginDir"
              # install, not cp: store files are mode 0444, and Jellyfin rewrites
              # meta.json on every start. A read-only copy aborts server startup.
              install -m 644 ${autheliaPluginRelease}/Authelia-Auth.dll ${autheliaPluginRelease}/meta.json "$pluginDir/"
              install -m 644 ${autheliaPluginLogo} "$pluginDir/logo.png"
            fi

            chmod 644 "$pluginDir/Authelia-Auth.dll" "$pluginDir/meta.json" "$pluginDir/logo.png" 2>/dev/null || true


          '';
        };
        createBackup = pkgs.writeShellApplication {
          name = "jellyfin-create-backup";
          runtimeInputs = [
            pkgs.curl
            pkgs.jq
            pkgs.coreutils
          ];
          text = ''
            set -euo pipefail
            key=$(cat ${jellyfinBackupKeyFile})
            response=$(curl -fsS -X POST \
              -H "Authorization: MediaBrowser Client=Backup, Device=JellyfinBackup, DeviceId=jellyfin-backup, Version=1, Token=$key" \
              -H "Content-Type: application/json" \
              -d '{}' \
              ${servicesLib.serviceUrl cfg config "jellyfin"}/Backup/Create)
            path=$(jq -er '.Path | strings | select(length > 0)' <<< "$response")
            filename=$(basename "$path")
            case "$filename" in
              jellyfin-backup-*.zip) ;;
              *) echo "unexpected Jellyfin backup response" >&2; exit 1 ;;
            esac
            archive=${lib.escapeShellArg service.backup.path}/"$filename"
            test -s "$archive"
            echo "native Jellyfin backup created: $filename"
          '';
        };
      in
      {
        config = lib.mkMerge [
          {
            sops.secrets.jellyfinBackupKey = {
              sopsFile = ../../../secrets/jellyfin.sops.yaml;
              owner = "root";
              mode = "0400";
            };

            containers.jellyfin = servicesLib.mkContainer {
              inherit cfg;
              name = "jellyfin";
              privateUsers = "pick";
              forwardPorts = [
                {
                  protocol = "tcp";
                  hostPort = 8096;
                  containerPort = 8096;
                }
              ];
              bindMounts = {
                "/var/lib/jellyfin" = {
                  hostPath = "${cfg.configDir}/jellyfin";
                  isReadOnly = false;
                };
                "/data" = {
                  hostPath = cfg.mediaPortalDir;
                  isReadOnly = false;
                };
                # allowedDevices only sets cgroup policy; without this bind
                # mount no /dev/dri nodes exist inside the container.
                "/dev/dri" = {
                  hostPath = "/dev/dri";
                  isReadOnly = true;
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

                systemd.services.jellyfin.serviceConfig.ExecStartPre = [
                  (lib.getExe seedAutheliaPlugin)
                ];

                hardware.graphics = {
                  enable = true;
                };

                users.users.jellyfin.extraGroups = [
                  "video"
                  "render"
                ];
              };
            };

            systemd.services."container@jellyfin".serviceConfig = {
              CPUQuota = "100%";
              CPUWeight = 20;
              IOWeight = 50;
              Nice = 10;
            };
          }
          (servicesLib.mkBackupJob {
            name = "jellyfin";
            description = "jellyfin backup via native API";
            backupDir = service.backup.path;
            inherit createBackup;
            filePattern = "jellyfin-backup-*.zip";
          })
        ];
      };
  };
}
