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
      "${cfg.dataDir}/authelia/config:/config:rw,Z"
      "${cfg.dataDir}/authelia/secrets:/secrets:rw,Z"
    ];
    extraPodmanArgs = [
      "--requires=valkey"
    ];
  };
  "valkey" = {
    image = "docker.io/valkey/valkey:7.2-alpine";
    environment = {
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}/authelia/valkey:/data:rw,Z"
    ];
    userNS = "repparw";
    exec = "valkey-server --save 60 1 --loglevel warning";
  };
}
