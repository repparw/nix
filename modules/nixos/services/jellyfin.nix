{ cfg, ... }:
{
  "jellyfin" = {
    image = "docker.io/linuxserver/jellyfin:latest";
    environment = {
      "DOCKER_MODS" = "linuxserver/mods:jellyfin-amd";
      "JELLYFIN_PublishedServerUrl" = "jellyfin.${cfg.domain}";
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}/media:/data/media:ro"
      "${cfg.configDir}/jellyfin:/config"
    ];
    extraOptions = [
      "--device=/dev/dri:/dev/dri:rwm"
      "--health-cmd=curl -f http://localhost:8096/health || exit 1"
    ];
    labels = {
      "traefik.http.services.jellyfin.loadbalancer.server.port" = "8096";
      "traefik.http.routers.jellyfin.middlewares" = "";
    };
  };
}
