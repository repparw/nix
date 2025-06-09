{ cfg, config, ... }:
{
  "changedetection" = {
    image = "docker.io/linuxserver/changedetection.io:latest";
    environment = {
      "TZ" = cfg.timezone;
      "BASE_URL" = "https://${cfg.domain}";
      "HIDE_REFERER" = "true";
      "PLAYWRIGHT_DRIVER_URL" = "ws://sockpuppetbrowser:3000";
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "LC_ALL" = "en_US.UTF-8";
    };
    volumes = [
      "${cfg.configDir}/changedetection:/config"
    ];
    dependsOn = [
      "sockpuppetbrowser"
    ];
    labels = {
      "glance.id" = "changedetection";
    };
  };
  "sockpuppetbrowser" = {
    image = "docker.io/dgtlmoon/sockpuppetbrowser:latest";
    environment = {
      "SCREEN_WIDTH" = "1920";
      "SCREEN_HEIGHT" = "1024";
      "SCREEN_DEPTH" = "16";
      "MAX_CONCURRENT_CHROME_PROCESSES" = "10";
    };
    labels = {
      "glance.parent" = "changedetection";
      "traefik.enable" = "false";
    };
  };
}
