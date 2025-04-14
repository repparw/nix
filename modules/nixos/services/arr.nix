{cfg}: {
  "bazarr" = {
    image = "docker.io/linuxserver/bazarr:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}/bazarr:/config:rw"
      "${cfg.dataDir}/data:/data:rw"
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
  "prowlarr" = {
    image = "docker.io/linuxserver/prowlarr:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}/prowlarr:/config:rw"
    ];
  };
  "qbittorrent" = {
    image = "docker.io/hotio/qbittorrent:latest";
    environment = {
      "PUID" = "1000";
      "PGID" = "100";
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}/data/torrents:/data/torrents:rw"
      "${cfg.dataDir}/qbittorrent:/config:rw"
    ];
    ports = [
      "127.0.0.1:54536:54536/tcp"
    ];
  };
  "radarr" = {
    image = "docker.io/linuxserver/radarr:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}/data/:/data:rw"
      "${cfg.dataDir}/radarr:/config:rw"
    ];
    dependsOn = [
      "qbittorrent"
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
      "${cfg.dataDir}/data:/data:rw"
      "${cfg.dataDir}/sonarr:/config:rw"
    ];
    dependsOn = [
      "qbittorrent"
    ];
  };
}
