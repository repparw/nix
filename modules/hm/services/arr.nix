{cfg}: {
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
    #dependsOn = [ "qbittorrent" ];
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
    #dependsOn = [ "qbittorrent" ];
  };
}
