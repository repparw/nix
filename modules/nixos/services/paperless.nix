{cfg}: {
  "broker" = {
    image = "docker.io/library/redis:7";
    volumes = [
      "${cfg.dataDir}/paper/redis:/data:rw"
    ];
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
    };
    volumes = [
      "${cfg.dataDir}/paper/data:/usr/src/paperless/data:rw"
      "${cfg.dataDir}/paper/export:/usr/src/paperless/export:rw"
      "${cfg.dataDir}/paper/media:/usr/src/paperless/media:rw"
    ];
    dependsOn = ["broker" "paperdb"];
  };
  "paperdb" = {
    image = "docker.io/library/postgres:15";
    environment = {
      "POSTGRES_DB" = "paperless";
      "POSTGRES_PASSWORD" = "paperless";
      "POSTGRES_USER" = "paperless";
    };
    volumes = [
      "${cfg.dataDir}/paper/pg:/var/lib/postgresql/data:rw"
    ];
  };
}
