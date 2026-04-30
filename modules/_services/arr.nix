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
      "${cfg.externalDataDir}:/data/seagate"
    ];
    healthCmd = "curl -f http://localhost:6767/bazarr/api/status";
  };
  # "listenarr" = {
  #   image = "ghcr.io/listenarrs/listenarr:canary";
  #   environment = {
  #     "PUID" = cfg.user;
  #     "PGID" = cfg.group;
  #     "TZ" = cfg.timezone;
  #   };
  #   volumes = [
  #     "${cfg.configDir}/listenarr:/app/config"
  #     "${cfg.dataDir}/media/audiobooks:/audiobooks"
  #     "${cfg.dataDir}/torrents:/downloads"
  #   ];
  #   healthCmd = "wget --no-verbose --tries=1 --spider http://localhost:4545/health";
  #   labels = {
  #     "traefik.http.services.listenarr.loadbalancer.server.port" = "4545";
  #   };
  # };
  "profilarr" = {
    image = "docker.io/santiagosayshey/profilarr:latest";
    environment = {
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.configDir}/profilarr:/config"
    ];
    healthCmd = "wget --no-verbose --tries=1 --spider http://localhost:6868/health";
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
    healthCmd = "curl -f http://localhost:9696/ping";
  };
  "qbittorrent" = {
    image = "docker.io/linuxserver/qbittorrent:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
      "DOCKER_MODS" = "ghcr.io/vuetorrent/vuetorrent-lsio-mod:latest";
      "TORRENTING_PORT" = "54535";
    };
    volumes = [
      "${cfg.configDir}/downloading:/downloading"
      "${cfg.dataDir}/torrents:/data/torrents"
      "${cfg.configDir}/qbittorrent:/config/qBittorrent"
    ];
    ports = [
      "54535:54535/tcp"
      "54535:54535/udp"
    ];
    healthCmd = "curl -f http://localhost:8080/api/v2/app/version";
    labels = {
      "traefik.http.routers.qbittorrent.rule" = "Host(`qbit.${cfg.domain}`)";
      "traefik.http.services.qbittorrent.loadbalancer.server.port" = "8080";
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
      "${cfg.externalDataDir}:/data/seagate"
      "${cfg.configDir}/radarr:/config"
    ];
    healthCmd = "curl -f http://localhost:7878/ping";
  };
  # "seerr" = {
  #   image = "docker.io/seerr/seerr:latest";
  #   environment = {
  #     "TZ" = cfg.timezone;
  #   };
  #   volumes = [
  #     "${cfg.configDir}/seerr:/app/config"
  #   ];
  #   labels = {
  #     "traefik.http.routers.seerr.middlewares" = "";
  #   };
  #   healthCmd = "wget --no-verbose --tries=1 --spider http://localhost:5055/api/v1/status";
  # };
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
      "${cfg.externalDataDir}:/data/seagate"
      "${cfg.configDir}/sonarr:/config"
    ];
    healthCmd = "curl -f http://localhost:8989/ping";
  };
}
