{cfg}: {
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
    extraPodmanArgs = [
      "--device=/dev/dri:/dev/dri:rwm"
    ];
  };
}
