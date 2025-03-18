{
  pkgs,
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.services.dlsuite;
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
      enable = true;
      autoPrune.enable = true;
      storageDriver = "btrfs";
      rootless.enable = true;
      rootless.setSocketVariable = true;
    };
    virtualisation.oci-containers.backend = "docker";
    virtualisation.oci-containers.containers = {
      "authelia" = {
        image = "docker.io/authelia/authelia:latest";
        environment = {
          "AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE" = "/secrets/JWT_SECRET";
          "AUTHELIA_SESSION_SECRET_FILE" = "/secrets/SESSION_SECRET";
          "AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE" = "/secrets/STORAGE_ENCRYPTION_KEY";
          "PGID" = cfg.group;
          "PUID" = cfg.user;
          "TZ" = cfg.timezone;
        };
        volumes = [
          "${cfg.dataDir}/authelia/config:/config:rw,Z"
          "${cfg.dataDir}/authelia/secrets:/secrets:rw,Z"
        ];
        dependsOn = [
          "valkey"
        ];
        log-driver = "journald";
        extraOptions = [
          "--network-alias=authelia"
          "--network=dlsuite"
        ];
      };
      "bazarr" = {
        image = "docker.io/linuxserver/bazarr:latest";
        environment = {
          "PGID" = cfg.group;
          "PUID" = cfg.user;
          "TZ" = cfg.timezone;
        };
        volumes = [
          "${cfg.dataDir}/bazarr:/config:rw,Z"
          "${cfg.dataDir}/data:/data:rw,z"
        ];
        log-driver = "journald";
        extraOptions = [
          "--network-alias=bazarr"
          "--network=dlsuite"
        ];
      };
      "broker" = {
        image = "docker.io/library/redis:7";
        volumes = [
          "${cfg.dataDir}/paper/redis:/data:rw,Z"
        ];
        log-driver = "journald";
        extraOptions = [
          "--network-alias=broker"
          "--network=dlsuite"
        ];
      };
      "changedetection" = {
        image = "docker.io/linuxserver/changedetection.io";
        environment = {
          "PUID" = cfg.user;
          "PGID" = cfg.group;
          "TZ" = cfg.timezone;
          "BASE_URL" = "https://${cfg.domain}";
          "HIDE_REFERER" = "true";
          #"PLAYWRIGHT_DRIVER_URL" = "ws://playwright:3000";
          #"WEBDRIVER_URL" = "http://playwright:3000/wd/hub";
        };
        volumes = [
          "${cfg.dataDir}/changedetection:/config:rw,Z"
        ];
        log-driver = "journald";
        extraOptions = [
          "--network-alias=changedetection"
          "--network=dlsuite"
        ];
      };
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
        log-driver = "journald";
        extraOptions = [
          "--network-alias=ddclient"
          "--network=dlsuite"
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
        log-driver = "journald";
        extraOptions = [
          "--network-alias=diun"
          "--network=dlsuite"
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
        log-driver = "journald";
        extraOptions = [
          "--network-alias=flaresolverr"
          "--network=dlsuite"
        ];
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
        log-driver = "journald";
        extraOptions = [
          "--network-alias=freshrss"
          "--network=dlsuite"
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
        log-driver = "journald";
        extraOptions = [
          "--device=/dev/dri:/dev/dri:rwm"
          "--network-alias=jellyfin"
          "--network=dlsuite"
        ];
      };
      "mercury" = {
        image = "docker.io/wangqiru/mercury-parser-api:latest";
        log-driver = "journald";
        extraOptions = [
          "--network-alias=mercury"
          "--network=dlsuite"
        ];
      };
      "paperdb" = {
        image = "docker.io/library/postgres:15";
        environment = {
          "POSTGRES_DB" = "paperless";
          "POSTGRES_PASSWORD" = "paperless";
          "POSTGRES_USER" = "paperless";
        };
        volumes = [
          "${cfg.dataDir}/paper/pg:/var/lib/postgresql/data:rw,Z"
        ];
        log-driver = "journald";
        extraOptions = [
          "--network-alias=paperdb"
          "--network=dlsuite"
        ];
      };
      "paperless" = {
        image = "docker.io/paperlessngx/paperless-ngx:latest";
        environment = {
          "PAPERLESS_DBHOST" = "paperdb";
          "PAPERLESS_DISABLE_REGULAR_LOGIN" = "1";
          "PAPERLESS_ENABLE_HTTP_REMOTE_USER" = "true";
          "PAPERLESS_HTTP_REMOTE_USER_HEADER_NAME" = "HTTP_REMOTE_USER";
          "PAPERLESS_LOGOUT_REDIRECT_URL" = "https://auth.${cfg.domain}/logout";
          "PAPERLESS_OCR_LANGUAGE" = "spa";
          "PAPERLESS_REDIS" = "redis://broker:6379";
          "PAPERLESS_TIME_ZONE" = cfg.timezone;
          "PAPERLESS_URL" = "https://paper.${cfg.domain}";
          "USERMAP_GID" = cfg.group;
          "USERMAP_UID" = cfg.user;
        };
        volumes = [
          "${cfg.dataDir}/paper/data:/usr/src/paperless/data:rw,Z"
          "${cfg.dataDir}/paper/export:/usr/src/paperless/export:rw,Z"
          "${cfg.dataDir}/paper/media:/usr/src/paperless/media:rw,Z"
          "/home/repparw/Documents/consume:/usr/src/paperless/consume:rw,Z"
        ];
        dependsOn = [
          "broker"
          "paperdb"
        ];
        log-driver = "journald";
        extraOptions = [
          "--network-alias=paperless"
          "--network=dlsuite"
        ];
      };
      # "playwright" = {
      #   image = "docker.io/browserless/chrome:1.60-chrome-stable";
      #   environment = {
      #     "CHROME_REFRESH_TIME" = "600000";
      #     "CONNECTION_TIMEOUT" = "300000";
      #     "DEFAULT_BLOCK_ADS" = "true";
      #     "DEFAULT_IGNORE_HTTPS_ERRORS" = "true";
      #     "DEFAULT_STEALTH" = "true";
      #     "ENABLE_DEBUGGER" = "false";
      #     "MAX_CONCURRENT_SESSIONS" = "10";
      #     "PREBOOT_CHROME" = "true";
      #     "SCREEN_DEPTH" = "16";
      #     "SCREEN_HEIGHT" = "1024";
      #     "SCREEN_WIDTH" = "1920";
      #   };
      #   log-driver = "journald";
      #   extraOptions = [
      #     "--health-cmd=curl -f http://localhost:3000"
      #     "--health-interval=30s"
      #     "--health-retries=5"
      #     "--health-start-period=10s"
      #     "--health-timeout=10s"
      #     "--network-alias=playwright"
      #     "--network=dlsuite"
      #   ];
      # };
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
        log-driver = "journald";
        extraOptions = [
          "--network-alias=prowlarr"
          "--network=dlsuite"
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
        log-driver = "journald";
        extraOptions = [
          "--network-alias=qbittorrent"
          "--network=dlsuite"
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
        log-driver = "journald";
        extraOptions = [
          "--network-alias=radarr"
          "--network=dlsuite"
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
        log-driver = "journald";
        extraOptions = [
          "--network-alias=sonarr"
          "--network=dlsuite"
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
        log-driver = "journald";
        extraOptions = [
          "--add-host=host.docker.internal:host-gateway"
          "--cap-add=NET_ADMIN"
          "--network-alias=swag"
          "--network=dlsuite"
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
        log-driver = "journald";
        extraOptions = [
          "--network-alias=valkey"
          "--network=dlsuite"
        ];
      };
    };
    # Services
    systemd.services = let
      containerSuffixes = [
        "authelia"
        "bazarr"
        "broker"
        "changedetection"
        "ddclient"
        "diun"
        "flaresolverr"
        "freshrss"
        "jellyfin"
        "mercury"
        "paperdb"
        "paperless"
        "playwright"
        "prowlarr"
        "qbittorrent"
        "radarr"
        "sonarr"
        "swag"
        "valkey"
      ];

      mkSystemService = suffix: {
        "docker-${suffix}" = {
          serviceConfig = {
            Restart = lib.mkOverride 500 "always";
          };
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

      systemdServices = builtins.foldl' lib.recursiveUpdate {} (map mkSystemService containerSuffixes);
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
