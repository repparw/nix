{ cfg, config, ... }:
{
  "karakeep" = {
    image = "ghcr.io/karakeep-app/karakeep:release";
    environment = {
      "TZ" = cfg.timezone;
      "DATA_DIR" = "/data";
      "MEILI_ADDR" = "http://meilisearch:7700";
      "BROWSER_WEB_URL" = "http://chrome:9222";
      "NEXTAUTH_URL" = "https://karakeep.${cfg.domain}";
    };
    environmentFiles = [
      config.sops.secrets.karakeep.path
    ];
    volumes = [
      "${cfg.dataDir}/karakeep:/data"
    ];
    labels = {
      "traefik.http.routers.karakeep.rule" = "Host(`karakeep.${cfg.domain}`)";
      "traefik.http.routers.karakeep.tls" = "true";
    };
  };
  "chrome" = {
    image = "gcr.io/zenika-hub/alpine-chrome:124";
    extraOptions = [
      "--no-sandbox"
      "--disable-gpu"
      "--disable-dev-shm-usage"
      "--remote-debugging-address=0.0.0.0"
      "--remote-debugging-port=9222"
      "--hide-scrollbars"
    ];
    labels = {
      "glance.parent" = "karakeep";
      "traefik.enable" = "false";
    };
  };
  "meilisearch" = {
    image = "docker.io/getmeili/meilisearch:v1.13.3";
    environment = {
      "MEILI_NO_ANALYTICS" = "true";
    };
    environmentFiles = [
      config.sops.secrets.karakeep.path
    ];
    volumes = [
      "${cfg.dataDir}/meilisearch:/meili_data"
    ];
    labels = {
      "glance.parent" = "karakeep";
      "traefik.enable" = "false";
    };
  };
}
