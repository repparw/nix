{cfg}: {
  "freshrss" = {
    image = "docker.io/linuxserver/freshrss:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.configDir}/freshrss:/config"
    ];
    extraOptions = [
      "--health-cmd=curl -f http://localhost:80/api/greader.php || exit 1"
    ];
  };
  "mercury" = {
    image = "docker.io/wangqiru/mercury-parser-api:latest";
  };
}
