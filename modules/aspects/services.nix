{
  lib,
  ...
}:
{
  den.aspects.nixos-services = {
    nixos =
      { config, pkgs, ... }:
      let
        cfg = config.modules.services;
      in
      {
        options.modules.services = {
          rootDir = lib.mkOption {
            type = lib.types.path;
            default = "/home/containers";
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
            description = "UID to map to inside the container namespace. Defaults to 0 (root).";
          };

          group = lib.mkOption {
            type = lib.types.str;
            default = "0";
            description = "GID to map to inside the container namespace. Defaults to 0 (root).";
          };

          podmanSocket = lib.mkOption {
            type = lib.types.str;
            default = "/run/podman/podman.sock";
            description = "Path to the podman socket to mount in containers";
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
            boot.kernel.sysctl = {
              "net.ipv4.ip_unprivileged_port_start" = 80;
            };

            environment.systemPackages = with pkgs; [ slirp4netns ];

            systemd.timers.podman-auto-update.wantedBy = [ "multi-user.target" ];

            networking.firewall.interfaces."podman*".allowedUDPPorts = [ 53 ];

            networking.hosts."192.168.0.18" = lib.attrValues serviceHostnames ++ [
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
        config,
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

        podmanSocket = "/run/user/${
          toString osConfig.users.users.${config.home.username}.uid
        }/podman/podman.sock";

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

            extraOpts = attrs.extraOptions or [ ];
            quadletContainerConfig = lib.filterAttrs (n: v: v != null) {
              HealthCmd = attrs.healthCmd or null;
              HealthInterval = attrs.healthInterval or null;
              HealthTimeout = attrs.healthTimeout or null;
              HealthRetries = attrs.healthRetries or null;
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
            extraPodmanArgs = extraOpts;
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
            inherit podmanSocket;
          })
        ) { } containersList;

        containers = lib.mapAttrs mkContainer rawContainers;
      in
      {
        systemd.user.sockets.podman = {
          Unit = {
            Description = "Podman API Socket";
            Documentation = "man:podman-system-service(1)";
          };
          Socket = {
            ListenStream = "%t/podman/podman.sock";
            SocketMode = "0660";
          };
          Install = {
            WantedBy = [ "sockets.target" ];
          };
        };

        services.podman = {
          enable = true;
          settings.containers = {
            network = {
              default_rootless_network_cmd = "slirp4netns";
            };
          };
          settings.storage = {
            storage = {
              driver = "btrfs";
            };
          };
          inherit containers;
          networks.services = {
            driver = "bridge";
          };
        };
      };
  };
}
