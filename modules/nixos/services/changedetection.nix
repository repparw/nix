{cfg}: {
  "changedetection" = {
    image = "docker.io/dgtlmoon/changedetection.io:latest";
    environment = {
      "TZ" = cfg.timezone;
      "BASE_URL" = "https://${cfg.domain}";
      "HIDE_REFERER" = "true";
      "PLAYWRIGHT_DRIVER_URL" = "ws://sockpuppetbrowser:3000";
    };
    volumes = [
      "${cfg.configDir}/changedetection:/datastore:rw"
    ];
    dependsOn = [
      "sockpuppetbrowser"
    ];
  };
  "sockpuppetbrowser" = {
    image = "docker.io/dgtlmoon/sockpuppetbrowser:latest";
    environment = {
      "SCREEN_WIDTH" = "1920";
      "SCREEN_HEIGHT" = "1024";
      "SCREEN_DEPTH" = "16";
      "MAX_CONCURRENT_CHROME_PROCESSES" = "10";
    };
  };
}
