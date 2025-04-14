{cfg}: {
  "freshrss" = {
    image = "docker.io/linuxserver/freshrss:latest";
    environment = {
      "PGID" = cfg.group;
      "PUID" = cfg.user;
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}/freshrss:/config:rw,Z"
    ];
  };
  "mercury" = {
    image = "docker.io/wangqiru/mercury-parser-api:latest";
  };
}
