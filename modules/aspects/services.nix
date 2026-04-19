{
  lib,
  ...
}:
{
  den.aspects.nixos-services = {
    nixos =
      { config, ... }:
      let
        cfg = config.modules.services;
      in
      {
        options.modules.services = {
          rootDir = lib.mkOption {
            type = lib.types.path;
            default = "/home/dlsuite";
            description = "Root directory for the containers";
          };

          dataDir = lib.mkOption {
            type = lib.types.path;
            default = "${cfg.rootDir}/data";
            description = "Directory to store container data";
          };

          externalDataDir = lib.mkOption {
            type = lib.types.path;
            default = "/mnt/seagate";
            description = "Directory where external library is";
          };

          configDir = lib.mkOption {
            type = lib.types.path;
            default = "${cfg.rootDir}/config";
            description = "Directory to store container config";
          };

          timezone = lib.mkOption {
            type = lib.types.str;
            default = "America/Argentina/Buenos_Aires";
            description = "Timezone for containers";
          };

          domain = lib.mkOption {
            type = lib.types.str;
            default = "repparw.com";
            description = "Base domain for the services";
          };

          user = lib.mkOption {
            type = lib.types.str;
            default = "1000";
            description = "User to run the containers";
          };

          group = lib.mkOption {
            type = lib.types.str;
            default = "100";
            description = "Group to run the containers";
          };
        };

        config = (
          let
            serviceFiles =
              lib.mapAttrs'
                (name: _: lib.nameValuePair (lib.removeSuffix ".nix" name) (import (../_services + "/${name}")))
                (
                  lib.filterAttrs (
                    name: type: type == "regular" && lib.hasSuffix ".nix" name && !(lib.hasPrefix "_" name)
                  ) (builtins.readDir ../_services)
                );

            extractHostname = rule: lib.removeSuffix "`)" (lib.removePrefix "Host(`" rule);

            getTraefikRule =
              name: attrs: attrs.labels."traefik.http.routers.${name}.rule" or "Host(`${name}.${cfg.domain}`)";

            mkContainer =
              name: attrs:
              let
                traefikRule = getTraefikRule name attrs;
                hostname = extractHostname traefikRule;
                defaultTraefikLabels = {
                  "traefik.enable" = lib.mkDefault "true";
                  "traefik.http.routers.${name}.tls" = "true";
                  "traefik.http.routers.${name}.rule" = lib.mkDefault traefikRule;
                  "traefik.http.routers.${name}.middlewares" = lib.mkDefault "authelia@file";
                };
              in
              lib.mkMerge [
                attrs
                {
                  extraOptions = (attrs.extraOptions or [ ]) ++ [
                    "--network-alias=${name}"
                    "--network=services"
                  ];
                  labels =
                    (attrs.labels or { })
                    // {
                      "io.containers.autoupdate" = "registry";

                      "glance.name" = name;
                      "glance.url" = lib.mkDefault "https://${hostname}";
                      "glance.icon" = lib.mkDefault "sh:${name}";
                      "glance.same-tab" = "true";
                    }
                    // defaultTraefikLabels;
                }
              ];

            containersList = lib.attrValues serviceFiles;

            rawContainers = lib.foldl' (acc: def: acc // (def { inherit cfg config; })) { } containersList;

            serviceHostnames = lib.mapAttrs (
              name: attrs:
              let
                rule = attrs.labels."traefik.http.routers.${name}.rule" or "Host(`${name}.${cfg.domain}`)";
              in
              extractHostname rule
            ) rawContainers;

            containerDefinitions = lib.mapAttrs mkContainer rawContainers;

            mkFileSystemMount = service: subPath: {
              "/home/repparw/.config/dlsuite/${service}" = {
                depends = [
                  "/"
                  "/mnt/hdd"
                ];
                device = "${cfg.configDir}/${subPath}";
                fsType = "none";
                options = [
                  "bind"
                  "ro"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=60"
                  "nofail"
                ];
              };
            };

            allContainers = map (name: "podman-${name}") (lib.attrNames containerDefinitions);

            hddDependent = [
              "podman-bazarr"
              "podman-jellyfin"
              "podman-paperless"
              "podman-qbittorrent"
              "podman-radarr"
              "podman-sonarr"
            ];
          in
          {
            systemd.timers.podman-auto-update.wantedBy = [ "multi-user.target" ];

            networking.firewall.interfaces."podman*".allowedUDPPorts = [ 53 ];

            networking.hosts."127.0.0.1" = lib.attrValues serviceHostnames ++ [
              cfg.domain
              "home.${cfg.domain}"
            ];

            systemd.targets.lazy-containers = {
              description = "non-essential container services";
            };

            systemd.timers.lazy-containers = {
              wantedBy = [ "multi-user.target" ];
              timerConfig = {
                OnActiveSec = "10s";
                Unit = "lazy-containers.target";
              };
            };


            virtualisation = {
              podman = {
                enable = true;
                autoPrune.enable = true;
                defaultNetwork.settings.dns_enabled = true;
              };


              containers = {
                enable = true;
                storage.settings = {
                  storage = {
                    driver = "btrfs";
                  };
                };
              };
            };

            fileSystems = lib.mkMerge [
              (mkFileSystemMount "authelia" "authelia")
              (mkFileSystemMount "listenarr" "listenarr")
              (mkFileSystemMount "bazarr" "bazarr/backup")
              (mkFileSystemMount "changedetection" "changedetection")
              (mkFileSystemMount "ddclient" "ddclient")
              (mkFileSystemMount "freshrss" "freshrss")
              (mkFileSystemMount "glance" "glance")
              (mkFileSystemMount "grafana" "grafana")
              (mkFileSystemMount "jellyfin" "jellyfin/data/data/backups")
              (mkFileSystemMount "jellyfin-plugins" "jellyfin/data/plugins")
              (mkFileSystemMount "karakeep" "karakeep")
              (mkFileSystemMount "ntfy" "ntfy")
              (mkFileSystemMount "open-webui" "open-webui")
              (mkFileSystemMount "paper" "paper/export")
              (mkFileSystemMount "profilarr" "profilarr/backups")
              (mkFileSystemMount "prometheus" "prometheus")
              (mkFileSystemMount "prowlarr" "prowlarr/Backups")
              (mkFileSystemMount "qbittorrent" "qbittorrent/config")
              (mkFileSystemMount "radarr" "radarr/Backups")
              (mkFileSystemMount "sonarr" "sonarr/Backups")
              (mkFileSystemMount "traefik" "traefik")
            ];
          }
        );
      };
  };
}
