{ cfg }:
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
    ports = [
      "127.0.0.1:8920:8920/tcp"
      "127.0.0.1:7359:7359/udp"
    ];
    extraOptions = [
      "--device=/dev/dri:/dev/dri:rwm"
      "--health-cmd=curl -f http://localhost:8096/health || exit 1"
    ];
  };
}
