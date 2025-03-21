	{ ... }: {
    "authelia" = {
      image = "docker.io/authelia/authelia:latest";
      environment = {
        "AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE" = "/secrets/JWT_SECRET";
        "AUTHELIA_SESSION_SECRET_FILE" = "/secrets/SESSION_SECRET";
        "AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE" = "/secrets/STORAGE_ENCRYPTION_KEY";
        "PGID" = cfg.group;
        "PUID" = cfg.user;
        "TZ" = cfg.timezone;
      };
      volumes = [
        "${cfg.dataDir}/authelia/config:/config:rw,Z"
        "${cfg.dataDir}/authelia/secrets:/secrets:rw,Z"
      ];
      dependsOn = [
        "valkey"
      ];
    };
    };
