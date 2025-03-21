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
}
