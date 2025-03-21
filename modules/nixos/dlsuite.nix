{
  pkgs,
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.services.dlsuite;

  containerDefaults = {
    podman.user = "dlsuite";
    podman.sdnotify = "container"; # Enable sdnotify for all containers
    log-driver = "journald";
    extraOptions = [
      "--network=dlsuite" #moved here
    ];
  };

  mkContainer = name: attrs:
    mkMerge [
      containerDefaults
      attrs
      {
        extraOptions =
          (attrs.extraOptions or [])
          ++ [
            "--network-alias=${name}"
          ];
      }
    ];
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
    users = {
      users.dlsuite = {
        isNormalUser = true;
        linger = true;
        home = "/home/docker";
        group = "dlsuite";
        uid = pkgs.lib.strings.toInt cfg.user;
      };
      groups.dlsuite = {
        gid = pkgs.lib.strings.toInt cfg.group;
      };
    };

    virtualisation = {
      podman = {
        enable = true;
        dockerCompat = true;
        autoPrune.enable = true;
        defaultNetwork.settings.dns_enabled = true;
      };
      containers.storage.settings.storage.driver = "btrfs";

      oci-containers.backend = "podman";
      oci-containers.containers = {
        authelia = mkContainer "authelia" {
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
        };
        bazarr = mkContainer "bazarr" {
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
        };
        broker = mkContainer "broker" {
          image = "docker.io/library/redis:7";
          volumes = [
            "${cfg.dataDir}/paper/redis:/data:rw,Z"
          ];
        };
        changedetection = mkContainer "changedetection" {
          image = "docker.io/dgtlmoon/changedetection.io:latest";
          environment = {
            "PUID" = cfg.user;
            "PGID" = cfg.group;
            "TZ" = cfg.timezone;
            "BASE_URL" = "https://${cfg.domain}";
            "HIDE_REFERER" = "true";
            "PLAYWRIGHT_DRIVER_URL" = "ws://sockpuppetbrowser:3000";
          };
          volumes = [
            "${cfg.dataDir}/changedetection:/datastore:rw,Z"
          ];
          dependsOn = [
            "sockpuppetbrowser"
          ];
        };
        ddclient = mkContainer "ddclient" {
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
        diun = mkContainer "diun" {
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
            "/run/podman/podman.sock:/var/run/docker.sock:ro"
          ];
        };
        flaresolverr = mkContainer "flaresolverr" {
          image = "docker.io/flaresolverr/flaresolverr:latest";
          environment = {
            "CAPTCHA_SOLVER" = "none";
            "LOG_HTML" = "false";
            "LOG_LEVEL" = "info";
            "TZ" = cfg.timezone;
          };
        };
        freshrss = mkContainer "freshrss" {
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
        jellyfin = mkContainer "jellyfin" {
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
        mercury = mkContainer "mercury" {
          image = "docker.io/wangqiru/mercury-parser-api:latest";
        };
        paperdb = mkContainer "paperdb" {
          image = "docker.io/library/postgres:15";
          environment = {
            "POSTGRES_DB" = "paperless";
            "POSTGRES_PASSWORD" = "paperless";
            "POSTGRES_USER" = "paperless";
          };
          volumes = [
            "${cfg.dataDir}/paper/pg:/var/lib/postgresql/data:rw,Z"
          ];
        };
        paperless = mkContainer "paperless" {
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
        };
        sockpuppetbrowser = mkContainer "sockpuppetbrowser" {
          image = "docker.io/dgtlmoon/sockpuppetbrowser:latest";
          environment = {
            "SCREEN_WIDTH" = "1920";
            "SCREEN_HEIGHT" = "1024";
            "SCREEN_DEPTH" = "16";
            "MAX_CONCURRENT_CHROME_PROCESSES" = "10";
          };
        };
        prowlarr = mkContainer "prowlarr" {
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
        qbittorrent = mkContainer "qbittorrent" {
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
        radarr = mkContainer "radarr" {
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
        sonarr = mkContainer "sonarr" {
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
        swag = mkContainer "swag" {
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
        valkey = mkContainer "valkey" {
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
        "sockpuppetbrowser"
        "prowlarr"
        "qbittorrent"
        "radarr"
        "sonarr"
        "swag"
        "valkey"
      ];

      mkSystemService = suffix: {
        "podman-${suffix}" = {
          serviceConfig = {
            Restart = lib.mkOverride 90 "always";
            RestartSec = lib.mkOverride 90 "5s";
          };
          startLimitBurst = 3;
          unitConfig = {
            StartLimitIntervalSec = lib.mkOverride 90 120;
          };
          after = [
            "podman-network-dlsuite.service"
          ];
          requires = [
            "podman-network-dlsuite.service"
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
        "podman-network-dlsuite" = {
          path = [pkgs.podman];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStop = "podman network rm -f dlsuite";
            User = "dlsuite";
          };
          script = ''
            podman network inspect dlsuite || podman network create dlsuite
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
