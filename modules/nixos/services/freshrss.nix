{cfg}: {
  "freshrss" = {
    image = "docker.io/linuxserver/freshrss:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}/freshrss:/config:rw"
    ];
  };
  "mercury" = {
    image = "docker.io/wangqiru/mercury-parser-api:latest";
  };
}
