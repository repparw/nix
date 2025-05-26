{ cfg }:
{
  "bazarr" = {
    image = "docker.io/linuxserver/bazarr:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.configDir}/bazarr:/config"
      "${cfg.dataDir}:/data"
    ];
    extraOptions = [
      "--health-cmd=curl -f http://localhost:6767/bazarr/api/status || exit 1"
    ];
    labels = {
      "glance.id" = "bazarr";
    };
  };
  "flaresolverr" = {
    image = "docker.io/flaresolverr/flaresolverr:latest";
    environment = {
      "CAPTCHA_SOLVER" = "none";
      "LOG_HTML" = "false";
      "LOG_LEVEL" = "info";
      "TZ" = cfg.timezone;
    };
    extraOptions = [
      "--health-cmd=curl -f http://localhost:8191/health || exit 1"
    ];
    labels = {
      "glance.parent" = "bazarr";
    };
  };
  "prowlarr" = {
    image = "docker.io/linuxserver/prowlarr:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.configDir}/prowlarr:/config"
    ];
    extraOptions = [
      "--health-cmd=curl -f http://localhost:9696/ping || exit 1"
    ];
  };
  "qbittorrent" = {
    image = "docker.io/hotio/qbittorrent:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}/torrents:/data/torrents"
      "${cfg.configDir}/qbittorrent:/config"
    ];
    ports = [
      "127.0.0.1:54536:54536/tcp"
    ];
    extraOptions = [
      "--health-cmd=curl -f http://localhost:8080/api/v2/app/version || exit 1"
    ];
    labels = {
      "glance.url" = "https://qbit.${cfg.domain}";
    };
  };
  "radarr" = {
    image = "docker.io/linuxserver/radarr:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}:/data"
      "${cfg.configDir}/radarr:/config"
    ];
    dependsOn = [
      "qbittorrent"
    ];
    extraOptions = [
      "--health-cmd=curl -f http://localhost:7878/ping || exit 1"
    ];
  };
  "sonarr" = {
    image = "docker.io/linuxserver/sonarr:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
    };
    volumes = [
      "/dev/rtc:/dev/rtc:ro"
      "${cfg.dataDir}:/data"
      "${cfg.configDir}/sonarr:/config"
    ];
    dependsOn = [
      "qbittorrent"
    ];
    extraOptions = [
      "--health-cmd=curl -f http://localhost:8989/ping || exit 1"
    ];
  };
}
