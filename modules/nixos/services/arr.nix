{ cfg, ... }:
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
  };
  "profilarr" = {
    image = "docker.io/santiagosayshey/profilarr:latest";
    environment = {
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.configDir}/profilarr:/config"
    ];
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
    image = "ghcr.io/hotio/qbittorrent:latest";
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
      "127.0.0.1:54535:54535/tcp"
    ];
    extraOptions = [
      "--health-cmd=curl -f http://localhost:8080/api/v2/app/version || exit 1"
    ];
    labels = {
      "traefik.http.routers.qbittorrent.rule" = "Host(`qbit.${cfg.domain}`)";
    };
  };
  "radarr" = {
    image = "docker.io/linuxserver/radarr:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
      "DOCKER_MODS" = "linuxserver/mods:radarr-striptracks";
      "STRIPTRACKS_ARGS" = "--audio :org:eng:und --subs :eng:spa";
    };
    volumes = [
      "${cfg.dataDir}:/data"
      "${cfg.configDir}/radarr:/config"
    ];
    extraOptions = [
      "--health-cmd=curl -f http://localhost:7878/ping || exit 1"
    ];
  };
  "seerr" = {
    image = "docker.io/seerr/seerr:latest";
    environment = {
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.configDir}/seerr:/app/config"
    ];
    labels = {
      "traefik.http.routers.seerr.middlewares" = "";
    };
    extraOptions = [
      "--init"
      "--health-cmd=wget --no-verbose --tries=1 --spider http://localhost:5055/api/v1/status || exit 1"
    ];
  };
  "sonarr" = {
    image = "docker.io/linuxserver/sonarr:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
      "DOCKER_MODS" = "linuxserver/mods:radarr-striptracks";
      "STRIPTRACKS_ARGS" = "--audio :org:eng:und --subs :eng:spa";
    };
    volumes = [
      "/dev/rtc:/dev/rtc:ro"
      "${cfg.dataDir}:/data"
      "${cfg.configDir}/sonarr:/config"
    ];
    extraOptions = [
      "--health-cmd=curl -f http://localhost:8989/ping || exit 1"
    ];
  };
}
