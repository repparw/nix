{ pkgs, lib, ... }:

{
  # Runtime
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerCompat = true;
    defaultNetwork.settings = {
      # Required for container networking to be able to use names.
      dns_enabled = true;
    };
  };
  virtualisation.oci-containers.backend = "podman";

  # Containers
  virtualisation.oci-containers.containers."authelia" = {
    image = "docker.io/authelia/authelia:latest";
    environment = {
      "AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE" = "/secrets/JWT_SECRET";
      "AUTHELIA_SESSION_SECRET_FILE" = "/secrets/SESSION_SECRET";
      "AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE" = "/secrets/STORAGE_ENCRYPTION_KEY";
      "PGID" = "131";
      "PUID" = "1001";
      "TZ" = "America/Argentina/Buenos_Aires";
    };
    volumes = [
      "/home/docker/authelia/config:/config:rw,Z"
      "/home/docker/authelia/secrets:/secrets:rw,Z"
    ];
    ports = [
      "9091:9091/tcp"
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
  systemd.services."podman-authelia" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."bazarr" = {
    image = "docker.io/linuxserver/bazarr:latest";
    environment = {
      "PGID" = "131";
      "PUID" = "1001";
      "TZ" = "America/Argentina/Buenos_Aires";
    };
    volumes = [
      "/home/docker/bazarr:/config:rw,Z"
      "/home/docker/data:/data:rw,z"
    ];
    ports = [
      "6767:6767/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=bazarr"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-bazarr" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."broker" = {
    image = "docker.io/library/redis:7";
    volumes = [
      "/home/docker/paper/redis:/data:rw,Z"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=broker"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-broker" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."changedetection" = {
    image = "docker.io/dgtlmoon/changedetection.io";
    environment = {
      "BASE_URL" = "https://repparw.com.ar";
      "HIDE_REFERER" = "true";
      "PGID" = "131";
      "PLAYWRIGHT_DRIVER_URL" = "ws://playwright:3000";
      "PORT" = "5000";
      "PUID" = "1001";
      "WEBDRIVER_URL" = "http://playwright:3000/wd/hub";
    };
    volumes = [
      "/var/lib/changedetection-io:/datastore:rw,Z"
    ];
    ports = [
      "5000:5000/tcp"
    ];
    dependsOn = [
      "playwright"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=changedetection"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-changedetection" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."db" = {
    image = "docker.io/library/postgres:15";
    environment = {
      "POSTGRES_DB" = "paperless";
      "POSTGRES_PASSWORD" = "paperless";
      "POSTGRES_USER" = "paperless";
    };
    volumes = [
      "/home/docker/paper/pg:/var/lib/postgresql/data:rw,Z"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=db"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-db" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."flaresolverr" = {
    image = "docker.io/flaresolverr/flaresolverr:latest";
    environment = {
      "CAPTCHA_SOLVER" = "none";
      "LOG_HTML" = "false";
      "LOG_LEVEL" = "info";
      "TZ" = "America/Argentina/Buenos_Aires";
    };
    ports = [
      "8191:8191/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=flaresolverr"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-flaresolverr" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."freshrss" = {
    image = "docker.io/linuxserver/freshrss:latest";
    environment = {
      "PGID" = "131";
      "PUID" = "1001";
      "TZ" = "America/Argentina/Buenos_Aires";
    };
    volumes = [
      "/home/docker/freshrss:/config:rw,Z"
    ];
    ports = [
      "81:80/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=freshrss"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-freshrss" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."grocy" = {
    image = "docker.io/linuxserver/grocy:latest";
    environment = {
      "PGID" = "131";
      "PUID" = "1001";
      "TZ" = "America/Argentina/Buenos_Aires";
    };
    volumes = [
      "/home/docker/grocy:/config:rw,Z"
    ];
    ports = [
      "9283:80/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=grocy"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-grocy" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."grupo10" = {
    image = "docker.io/library/postgres:16";
    environment = {
      "POSTGRES_DB" = "grupo10";
      "POSTGRES_PASSWORD" = "postgres";
      "POSTGRES_USER" = "postgres";
    };
    volumes = [
      "/home/docker/grupo10:/var/lib/postgresql/data:rw,Z"
    ];
    ports = [
      "5432:5432/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=grupo10"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-grupo10" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."jellyfin" = {
    image = "docker.io/linuxserver/jellyfin:latest";
    environment = {
      "DOCKER_MODS" = "linuxserver/mods:jellyfin-amd";
      "JELLYFIN_PublishedServerUrl" = "jellyfin.repparw.com.ar";
      "PGID" = "971";
      "PUID" = "974";
      "TZ" = "America/Argentina/Buenos_Aires";
    };
    volumes = [
      "/home/docker/data/media:/data/media:ro"
      "/home/docker/jellyfin:/config:rw,Z"
    ];
    ports = [
      "8096:8096/tcp"
      "8920:8920/tcp"
      "7359:7359/udp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--device=/dev/dri:/dev/dri:rwm"
      "--network-alias=jellyfin"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-jellyfin" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."mercury" = {
    image = "docker.io/wangqiru/mercury-parser-api:latest";
    ports = [
      "3000:3000/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=mercury"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-mercury" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."paperless" = {
    image = "docker.io/paperless-ngx/paperless-ngx:latest";
    environment = {
      "PAPERLESS_DBHOST" = "db";
      "PAPERLESS_DISABLE_REGULAR_LOGIN" = "1";
      "PAPERLESS_OCR_LANGUAGE" = "spa";
      "PAPERLESS_REDIS" = "redis://broker:6379";
      "PAPERLESS_TIME_ZONE" = "America/Argentina/Buenos_Aires";
      "PAPERLESS_URL" = "https://paper.repparw.com.ar";
      "USERMAP_GID" = "131";
      "USERMAP_UID" = "1001";
    };
    volumes = [
      "/home/docker/paper/data:/usr/src/paperless/data:rw,Z"
      "/home/docker/paper/export:/usr/src/paperless/export:rw,Z"
      "/home/docker/paper/media:/usr/src/paperless/media:rw,Z"
      "/home/repparw/Documents/consume:/usr/src/paperless/consume:rw,Z"
    ];
    ports = [
      "8000:8000/tcp"
    ];
    dependsOn = [
      "broker"
      "db"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=paperless"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-paperless" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."pgadmin" = {
    image = "docker.io/dpage/pgadmin4:latest";
    environment = {
      "PGADMIN_DEFAULT_EMAIL" = "admin@admin.com";
      "PGADMIN_DEFAULT_PASSWORD" = "admin";
    };
    ports = [
      "5050:80/tcp"
    ];
    dependsOn = [
      "grupo10"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=pgadmin"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-pgadmin" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."playwright" = {
    image = "docker.io/browserless/chrome:1.60-chrome-stable";
    environment = {
      "CHROME_REFRESH_TIME" = "600000";
      "CONNECTION_TIMEOUT" = "300000";
      "DEFAULT_BLOCK_ADS" = "true";
      "DEFAULT_IGNORE_HTTPS_ERRORS" = "true";
      "DEFAULT_STEALTH" = "true";
      "ENABLE_DEBUGGER" = "false";
      "MAX_CONCURRENT_SESSIONS" = "10";
      "PREBOOT_CHROME" = "true";
      "SCREEN_DEPTH" = "16";
      "SCREEN_HEIGHT" = "1024";
      "SCREEN_WIDTH" = "1920";
    };
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=[\"curl\",\"-f\",\"http://localhost:3000\"]"
      "--health-interval=30s"
      "--health-retries=5"
      "--health-start-period=10s"
      "--health-timeout=10s"
      "--network-alias=playwright"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-playwright" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."prowlarr" = {
    image = "docker.io/linuxserver/prowlarr:latest";
    environment = {
      "PGID" = "131";
      "PUID" = "1001";
      "TZ" = "America/Argentina/Buenos_Aires";
    };
    volumes = [
      "/home/docker/prowlarr:/config:rw,Z"
    ];
    ports = [
      "9696:9696/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=prowlarr"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-prowlarr" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."qbitttorrent" = {
    image = "docker.io/hotio/qbittorrent:latest";
    environment = {
      "PGID" = "131";
      "PUID" = "1001";
      "TZ" = "America/Argentina/Buenos_Aires";
    };
    volumes = [
      "/home/docker/data/torrents:/data/torrents:rw,z"
      "/home/docker/qbittorrent:/config:rw,Z"
    ];
    ports = [
      "54536:54536/tcp"
      "8080:8080/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=qbittorrent"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-qbitttorrent" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."radarr" = {
    image = "docker.io/linuxserver/radarr:latest";
    environment = {
      "PGID" = "131";
      "PUID" = "1001";
      "TZ" = "America/Argentina/Buenos_Aires";
    };
    volumes = [
      "/home/docker/data/:/data:rw,z"
      "/home/docker/radarr:/config:rw,Z"
    ];
    ports = [
      "7878:7878/tcp"
    ];
    dependsOn = [
      "qbitttorrent"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=radarr"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-radarr" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."sonarr" = {
    image = "docker.io/linuxserver/sonarr:latest";
    environment = {
      "PGID" = "131";
      "PUID" = "1001";
      "TZ" = "America/Argentina/Buenos_Aires";
    };
    volumes = [
      "/dev/rtc:/dev/rtc:ro"
      "/home/docker/data:/data:rw,z"
      "/home/docker/sonarr:/config:rw,Z"
    ];
    ports = [
      "8989:8989/tcp"
    ];
    dependsOn = [
      "qbitttorrent"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=sonarr"
      "--network=dlsuite"
    ];
  };
  systemd.services."podman-sonarr" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."swag" = {
    image = "docker.io/linuxserver/swag:latest";
    environment = {
      "DNSPLUGIN" = "cloudflare";
      "DOCKER_MODS" = "linuxserver/mods:universal-cron";
      "PGID" = "131";
      "PUID" = "1001";
      "SUBDOMAINS" = "wildcard";
      "TZ" = "America/Argentina/Buenos_Aires";
      "URL" = "repparw.com.ar";
      "VALIDATION" = "dns";
    };
    volumes = [
      "/home/docker/swag:/config:rw,Z"
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
  systemd.services."podman-swag" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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
  virtualisation.oci-containers.containers."valkey" = {
    image = "docker.io/valkey/valkey:7.2-alpine";
    environment = {
      "PGID" = "131";
      "PUID" = "1001";
      "TZ" = "America/Argentina/Buenos_Aires";
    };
    volumes = [
      "/home/docker/authelia/valkey:/data:rw,Z"
    ];
    ports = [
      "6379:6379/tcp"
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
  systemd.services."podman-valkey" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
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

  # Networks
  systemd.services."podman-network-dlsuite" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f dlsuite";
    };
    script = ''
      podman network inspect dlsuite || podman network create dlsuite
    '';
    partOf = [ "dlsuite.target" ];
    wantedBy = [ "dlsuite.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."dlsuite" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
