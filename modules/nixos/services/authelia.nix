{cfg}: {
  "authelia" = {
    image = "docker.io/authelia/authelia:latest";
    environment = {
      "AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE" = "/secrets/JWT_SECRET";
      "AUTHELIA_SESSION_SECRET_FILE" = "/secrets/SESSION_SECRET";
      "AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE" = "/secrets/STORAGE_ENCRYPTION_KEY";
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.configDir}/authelia/config:/config"
      "${cfg.configDir}/authelia/secrets:/secrets"
    ];
    dependsOn = [
      "valkey"
    ];
  };
  "valkey" = {
    image = "docker.io/valkey/valkey:7.2-alpine";
    environment = {
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.configDir}/authelia/valkey:/data"
    ];
    cmd = ["valkey-server" "--save" "60" "1" "--loglevel" "warning"];
    extraOptions = ["--health-cmd=nc -z localhost 6379 || exit 1"];
  };
}
