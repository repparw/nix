{
  pkgs,
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.services.dlsuite;

  mkContainer = name: attrs:
    mkMerge [
      {
        log-driver = "journald";
        networks = ["dlsuite"];
      }
      (attrs {inherit cfg;})
      {
        extraOptions =
          (attrs.extraOptions or [])
          ++ ["--network-alias=${name}"];
      }
    ];

  # List of container configurations
  containersList = [
    (import ./authelia.nix)
    (import ./bazarr.nix)
    (import ./changedetection.nix)
    (import ./ddclient.nix)
    (import ./diun.nix)
    (import ./flaresolverr.nix)
    (import ./freshrss.nix)
    (import ./jellyfin.nix)
    (import ./mercury.nix)
    (import ./paperless.nix)
    (import ./prowlarr.nix)
    (import ./qbittorrent.nix)
    (import ./radarr.nix)
    (import ./sonarr.nix)
    (import ./swag.nix)
    (import ./valkey.nix)
  ];

  # Merge all container definitions
  containerDefinitions =
    mapAttrs (name: attrs: mkContainer name attrs)
    (foldl' (acc: def: acc // def) {} containersList);

    "ddclient" = {
      image = "docker.io/linuxserver/ddclient:latest";
      environment = {
        "PGID" = cfg.group;
        "PUID" = cfg.user;
        "TZ" = cfg.timezone;
      };
      volumes = [
        "${cfg.dataDir}/ddclient:/config:rw,Z"
      ];
    };
    "diun" = {
      image = "docker.io/crazymax/diun:latest";
      environment = {
        "TZ" = cfg.timezone;
        "DIUN_WATCH_WORKERS" = "20";
        "DIUN_WATCH_SCHEDULE" = "@every 12h";
        "DIUN_PROVIDERS_DOCKER" = "true";
        "DIUN_PROVIDERS_DOCKER_WATCHBYDEFAULT" = "true";
        "DIUN_NOTIF_DISCORD_WEBHOOKURLFILE" = "/data/discord-webhook-url";
      };
      volumes = [
        "${cfg.dataDir}/diun:/data:rw,Z"
        "/var/run/docker.sock:/var/run/docker.sock:ro"
      ];
    };
    "flaresolverr" = {
      image = "docker.io/flaresolverr/flaresolverr:latest";
      environment = {
        "CAPTCHA_SOLVER" = "none";
        "LOG_HTML" = "false";
        "LOG_LEVEL" = "info";
        "TZ" = cfg.timezone;
      };
    };
    "freshrss" = {
      image = "docker.io/linuxserver/freshrss:latest";
      environment = {
        "PGID" = cfg.group;
        "PUID" = cfg.user;
        "TZ" = cfg.timezone;
      };
      volumes = [
        "${cfg.dataDir}/freshrss:/config:rw,Z"
      ];
    };
    "jellyfin" = {
      image = "docker.io/linuxserver/jellyfin:latest";
      environment = {
        "DOCKER_MODS" = "linuxserver/mods:jellyfin-amd";
        "JELLYFIN_PublishedServerUrl" = "jellyfin.${cfg.domain}";
        "PGID" = cfg.group;
        "PUID" = cfg.user;
        "TZ" = cfg.timezone;
      };
      volumes = [
        "${cfg.dataDir}/data/media:/data/media:ro"
        "${cfg.dataDir}/jellyfin:/config:rw,Z"
      ];
      ports = [
        "127.0.0.1:8920:8920/tcp"
        "127.0.0.1:7359:7359/udp"
      ];
      extraOptions = [
        "--device=/dev/dri:/dev/dri:rwm"
      ];
    };
    "mercury" = {
      image = "docker.io/wangqiru/mercury-parser-api:latest";
    };
    "prowlarr" = {
      image = "docker.io/linuxserver/prowlarr:latest";
      environment = {
        "PGID" = cfg.group;
        "PUID" = cfg.user;
        "TZ" = cfg.timezone;
      };
      volumes = [
        "${cfg.dataDir}/prowlarr:/config:rw,Z"
      ];
    };
    "qbittorrent" = {
      image = "docker.io/hotio/qbittorrent:latest";
      environment = {
        "PGID" = cfg.group;
        "PUID" = cfg.user;
        "TZ" = cfg.timezone;
      };
      volumes = [
        "${cfg.dataDir}/data/torrents:/data/torrents:rw,z"
        "${cfg.dataDir}/qbittorrent:/config:rw,Z"
      ];
      ports = [
        "127.0.0.1:54536:54536/tcp"
      ];
    };
    "radarr" = {
      image = "docker.io/linuxserver/radarr:latest";
      environment = {
        "PGID" = cfg.group;
        "PUID" = cfg.user;
        "TZ" = cfg.timezone;
      };
      volumes = [
        "${cfg.dataDir}/data/:/data:rw,z"
        "${cfg.dataDir}/radarr:/config:rw,Z"
      ];
      dependsOn = [
        "qbittorrent"
      ];
    };
    "sonarr" = {
      image = "docker.io/linuxserver/sonarr:latest";
      environment = {
        "PGID" = cfg.group;
        "PUID" = cfg.user;
        "TZ" = cfg.timezone;
      };
      volumes = [
        "/dev/rtc:/dev/rtc:ro"
        "${cfg.dataDir}/data:/data:rw,z"
        "${cfg.dataDir}/sonarr:/config:rw,Z"
      ];
      dependsOn = [
        "qbittorrent"
      ];
    };
    "swag" = {
      image = "docker.io/linuxserver/swag:latest";
      environment = {
        "DNSPLUGIN" = "cloudflare";
        "PGID" = cfg.group;
        "PUID" = cfg.user;
        "TZ" = cfg.timezone;
        "SUBDOMAINS" = "wildcard";
        "URL" = cfg.domain;
        "VALIDATION" = "dns";
      };
      volumes = [
        "${cfg.dataDir}/swag:/config:rw,Z"
        "/home/repparw/git/homepage:/config/www:rw,Z"
      ];
      ports = [
        "443:443/tcp"
        "80:80/tcp"
      ];
      extraOptions = [
        "--add-host=host.docker.internal:host-gateway"
        "--cap-add=NET_ADMIN"
      ];
    };
    "valkey" = {
      image = "docker.io/valkey/valkey:7.2-alpine";
      environment = {
        "PGID" = cfg.group;
        "PUID" = cfg.user;
        "TZ" = cfg.timezone;
      };
      volumes = [
        "${cfg.dataDir}/authelia/valkey:/data:rw,Z"
      ];
      cmd = [
        "valkey-server"
        "--save"
        "60"
        "1"
        "--loglevel"
        "warning"
      ];
    };
  };
in {
  options.services.dlsuite = {
    enable = mkEnableOption "dlsuite container stack";

    dataDir = mkOption {
      type = types.path;
      default = "/home/docker";
      description = "Directory to store container data";
    };

    timezone = mkOption {
      type = types.str;
      default = "America/Argentina/Buenos_Aires";
      description = "Timezone for containers";
    };

    domain = mkOption {
      type = types.str;
      default = "repparw.me";
      description = "Base domain for the services";
    };

    user = mkOption {
      type = types.str;
      default = "1001";
      description = "User to run containers as";
    };

    group = mkOption {
      type = types.str;
      default = "131";
      description = "Group to run containers as";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.docker = {
      autoPrune.enable = true;
      storageDriver = "btrfs";
    };

    virtualisation.oci-containers.backend = "docker";
    virtualisation.oci-containers.containers = containerDefinitions;

    users.users.dlsuite = {
      isNormalUser = true;
      uid = lib.strings.toInt cfg.user;
      group = "docker";
      home = "/home/docker";
      createHome = true;
      shell = pkgs.bash;
    };

    # Services
    systemd.services = let
      containerSuffixes = builtins.attrNames containerDefinitions;

      mkSystemService = suffix: {
        "docker-${suffix}" = {
          #serviceConfig = {
          #  Restart = lib.mkOverride 500 "always";
          #};
          after = [
            "docker-network-dlsuite.service"
          ];
          requires = [
            "docker-network-dlsuite.service"
          ];
          partOf = [
            "dlsuite.target"
          ];
          wantedBy = [
            "dlsuite.target"
          ];
        };
      };

      systemdServices =
        builtins.foldl' lib.recursiveUpdate {} (map mkSystemService containerSuffixes);
    in
      systemdServices
      // {
        # Networks
        "docker-network-dlsuite" = {
          path = [
            pkgs.docker
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStop = "docker network rm -f dlsuite";
          };
          script = ''
            docker network inspect dlsuite || docker network create dlsuite
          '';
          partOf = [
            "dlsuite.target"
          ];
          wantedBy = [
            "dlsuite.target"
          ];
        };
      };

    # Root service
    # When started, this will automatically create all resources and start
    # the containers. When stopped, this will teardown all resources.
    systemd.targets."dlsuite" = {
      unitConfig = {
        Description = "Root target generated by compose2nix.";
      };
      wantedBy = [
        "multi-user.target"
      ];
    };
  };
}
