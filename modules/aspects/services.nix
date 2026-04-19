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
            default = "0";
            description = "User to run the containers";
          };

          group = lib.mkOption {
            type = lib.types.str;
            default = "0";
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

            containersList = lib.attrValues serviceFiles;

            rawContainers = lib.foldl' (acc: def: acc // (def { inherit cfg config; })) { } containersList;

            serviceHostnames = lib.mapAttrs (
              name: attrs:
              let
                rule = attrs.labels."traefik.http.routers.${name}.rule" or "Host(`${name}.${cfg.domain}`)";
              in
              extractHostname rule
            ) rawContainers;

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

    homeManager =
      {
        osConfig,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = osConfig.modules.services;
        serviceDir = ../_services;

        serviceFiles =
          lib.mapAttrs'
            (name: _: lib.nameValuePair (lib.removeSuffix ".nix" name) (import (serviceDir + "/${name}")))
            (
              lib.filterAttrs (
                name: type: type == "regular" && lib.hasSuffix ".nix" name && !(lib.hasPrefix "_" name)
              ) (builtins.readDir serviceDir)
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
              "traefik.enable" = "true";
              "traefik.http.routers.${name}.tls" = "true";
              "traefik.http.routers.${name}.rule" = traefikRule;
              "traefik.http.routers.${name}.middlewares" = "authelia@file";
            };

            extraOpts = attrs.extraOptions or [ ];
            healthCmdOpt = lib.findFirst (opt: lib.hasPrefix "--health-cmd=" opt) null extraOpts;
            healthIntervalOpt = lib.findFirst (opt: lib.hasPrefix "--health-interval=" opt) null extraOpts;
            healthTimeoutOpt = lib.findFirst (opt: lib.hasPrefix "--health-timeout=" opt) null extraOpts;
            healthRetriesOpt = lib.findFirst (opt: lib.hasPrefix "--health-retries=" opt) null extraOpts;

            rawHealthCmd = if healthCmdOpt != null then lib.removePrefix "--health-cmd=" healthCmdOpt else null;
            healthCmd =
              if rawHealthCmd != null then
                lib.trim (lib.removeSuffix " || exit 1" (lib.removeSuffix "|| exit 1" rawHealthCmd))
              else
                null;
            healthInterval =
              if healthIntervalOpt != null then lib.removePrefix "--health-interval=" healthIntervalOpt else null;
            healthTimeout =
              if healthTimeoutOpt != null then lib.removePrefix "--health-timeout=" healthTimeoutOpt else null;
            healthRetries =
              if healthRetriesOpt != null then lib.removePrefix "--health-retries=" healthRetriesOpt else null;

            nonHealthOpts = lib.filter (
              opt:
              !(
                lib.hasPrefix "--health-cmd=" opt
                || lib.hasPrefix "--health-interval=" opt
                || lib.hasPrefix "--health-timeout=" opt
                || lib.hasPrefix "--health-retries=" opt
              )
            ) extraOpts;

            quadletContainerConfig = lib.filterAttrs (n: v: v != null) {
              HealthCmd = healthCmd;
              HealthInterval = healthInterval;
              HealthTimeout = healthTimeout;
              HealthRetries = healthRetries;
            };
          in
          {
            image = attrs.image;
            addCapabilities = attrs.addCapabilities or [ ];
            environment = attrs.environment or { };
            environmentFile = attrs.environmentFiles or [ ];
            volumes = attrs.volumes or [ ];
            ports = attrs.ports or [ ];
            labels =
              defaultTraefikLabels
              // {
                "io.containers.autoupdate" = "registry";
                "glance.name" = name;
                "glance.url" = "https://${hostname}";
                "glance.icon" = "sh:${name}";
                "glance.same-tab" = "true";
              }
              // (attrs.labels or { });
            extraPodmanArgs = nonHealthOpts;
            network = [ "services" ];
            networkAlias = [ name ];
            autoStart = true;
            autoUpdate = "registry";
            exec = if attrs ? cmd then lib.concatStringsSep " " attrs.cmd else null;
            extraConfig =
              if quadletContainerConfig != { } then { Container = quadletContainerConfig; } else { };
          };

        containersList = lib.attrValues serviceFiles;

        rawContainers = lib.foldl' (
          acc: def:
          acc
          // (def {
            inherit cfg;
            config = osConfig;
          })
        ) { } containersList;

        containers = lib.mapAttrs mkContainer rawContainers;
      in
      {
        services.podman = {
          enable = true;
          inherit containers;
          networks.services = {
            driver = "bridge";
          };
        };
      };
  };
}
