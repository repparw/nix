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
        autheliaProviderId = "Jellyfin.Plugin.Authelia_Auth.AutheliaAuthenticationProviderPlugin";
        defaultProviderId = "Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider";
        autheliaUserNames = [
          "galo"
          "bruni"
          "edgar"
          "repparw"
          "valen"
        ];
        autheliaUserList = lib.concatStringsSep ", " (map (name: "'${name}'") autheliaUserNames);

        # Runs before the server as the service user. Two responsibilities:
        #
        # 1. Seed the pinned plugin binaries when the live plugins tree is
        #    missing them (the 2026-09/10 upgrade window removed them). The
        #    plugin manager keeps owning the tree afterwards: auto-updates,
        #    meta.json reconciliation, and dashboard uninstalls all keep
        #    working. A deliberately uninstalled plugin reappears on the next
        #    start while this pin exists - remove the pin to hand the tree
        #    back to the dashboard.
        #
        # 2. One-time migration of existing accounts to the Authelia provider.
        #    Jellyfin routes each login to the provider stored on the user, so
        #    accounts stay on the default provider until re-pointed; the plugin
        #    only ever sees unknown usernames. Only accounts still on the
        #    default provider are touched, and the marker file keeps later
        #    restarts (or deliberate dashboard provider changes) from
        #    overriding live assignments. Local password hashes are preserved,
        #    so flipping a user back to the
        #    Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider
        #    id in the database instantly restores native authentication.
        initAutheliaAuth = pkgs.writeShellApplication {
          name = "jellyfin-authelia-init";
          runtimeInputs = with pkgs; [
            coreutils
            sqlite
          ];
          text = ''
            set -euo pipefail
            pluginDir='/var/lib/jellyfin/plugins/Authelia Authentication_1.0.17.0'
            db=/var/lib/jellyfin/data/jellyfin.db
            marker=/var/lib/jellyfin/data/.authelia-provider-migrated

            if [ ! -f "$pluginDir/Authelia-Auth.dll" ]; then
              echo "seeding Authelia Authentication 1.0.17.0 from the declarative source"
              mkdir -p "$pluginDir"
              # install, not cp: store files are mode 0444, and Jellyfin rewrites
              # meta.json on every start. A read-only copy aborts server startup.
              install -m 644 ${autheliaPluginRelease}/Authelia-Auth.dll ${autheliaPluginRelease}/meta.json "$pluginDir/"
              install -m 644 ${autheliaPluginLogo} "$pluginDir/logo.png"
            fi

            chmod 644 "$pluginDir/Authelia-Auth.dll" "$pluginDir/meta.json" "$pluginDir/logo.png" 2>/dev/null || true

            if [ -e "$marker" ]; then
              exit 0
            fi
            changed=$(sqlite3 "$db" "UPDATE Users SET AuthenticationProviderId = '${autheliaProviderId}'
              WHERE Username IN (${autheliaUserList})
                AND AuthenticationProviderId = '${defaultProviderId}';
              SELECT changes();")
            echo "re-pointed $changed account(s) to the Authelia authentication provider"
            touch "$marker"
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
                  (lib.getExe initAutheliaAuth)
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
