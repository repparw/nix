{cfg}: {
  "freshrss" = {
    image = "docker.io/linuxserver/freshrss:latest";
    environment = {
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
