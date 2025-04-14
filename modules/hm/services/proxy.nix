{cfg}: {
  "nginx" = {
    image = "docker.io/nginx/nginx:latest";
    environment = {
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}/nginx:/config:rw,Z"
    ];
  };
  "ddclient" = {
    image = "docker.io/linuxserver/ddclient:latest";
    environment = {
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}/ddclient:/config:rw,Z"
    ];
  };
}
