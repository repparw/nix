{cfg}: {
  "diun" = {
    image = "docker.io/crazymax/diun:latest";
    environment = {
      "TZ" = cfg.timezone;
      "DIUN_WATCH_WORKERS" = "20";
      "DIUN_WATCH_SCHEDULE" = "@every 12h";
      "DIUN_PROVIDERS_DOCKER" = "true";
      "DIUN_PROVIDERS_DOCKER_WATCHBYDEFAULT" = "true";
      "DIUN_NOTIF_NTFY_TOKENFILE" = "/data/diun-ntfy";
      "DIUN_NOTIF_NTFY_TOPIC" = "diun";
      "DIUN_NOTIF_NTFY_ENDPOINT" = "https://ntfy.${cfg.domain}";
    };
    volumes = [
      "${cfg.configDir}/diun:/data"
      "/run/podman/podman.sock:/var/run/docker.sock"
    ];
    labels = {
      "glance.hide" = "true";
    };
  };
}
