{ cfg, config, ... }:
{
  "broker" = {
    image = "docker.io/library/redis:7";
    volumes = [
      "${cfg.configDir}/paper/redis:/data"
    ];
    extraOptions = [
    ];
    labels = {
      "glance.parent" = "paperless";
      "traefik.enable" = "false";
    };
  };
  "paperless" = {
    image = "docker.io/paperlessngx/paperless-ngx:latest";
    environment = {
      "PAPERLESS_DBHOST" = "paperdb";
      "PAPERLESS_DISABLE_REGULAR_LOGIN" = "1";
      "PAPERLESS_ENABLE_HTTP_REMOTE_USER" = "true";
      "PAPERLESS_HTTP_REMOTE_USER_HEADER_NAME" = "HTTP_REMOTE_USER";
      "PAPERLESS_LOGOUT_REDIRECT_URL" = "https://auth.${cfg.domain}/logout";
      "PAPERLESS_OCR_LANGUAGE" = "spa";
      "PAPERLESS_REDIS" = "redis://broker:6379";
      "PAPERLESS_TIME_ZONE" = cfg.timezone;
      "PAPERLESS_URL" = "https://paper.${cfg.domain}";
      "USERMAP_UID" = cfg.user;
      "USERMAP_GID" = cfg.group;
    };
    volumes = [
      "${cfg.configDir}/paper/data:/usr/src/paperless/data"
      "${cfg.configDir}/paper/export:/usr/src/paperless/export"
      "${cfg.configDir}/paper/media:/usr/src/paperless/media"
    ];
    dependsOn = [
      "broker"
      "paperdb"
    ];
    extraOptions = [
      "--health-cmd=curl -f http://localhost:8000/api/ || exit 1"
    ];
    labels = {
      "glance.url" = "https://paper.${cfg.domain}";
      "traefik.http.routers.paperless.rule" = "Host(`paper.${cfg.domain}`)";
    };
  };
  "paperdb" = {
    image = "docker.io/library/postgres:15";
    environment = {
      "POSTGRES_DB" = "paperless";
      "POSTGRES_PASSWORD" = "paperless";
      "POSTGRES_USER" = "paperless";
    };
    volumes = [
      "${cfg.configDir}/paper/pg:/var/lib/postgresql/data"
    ];
    extraOptions = [
      "--health-cmd=pg_isready -U paperless || exit 1"
    ];
    labels = {
      "glance.parent" = "paperless";
      "traefik.enable" = "false";
    };
  };
}
