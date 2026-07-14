{
  cfg,
  config,
  lib,
  servicesLib,
  ...
}:
let
  service = cfg.definitions.authelia;
  authUrl = "https://${service.hostname}.${cfg.domain}";
  ingressPolicy = import ./ingress-policy.nix { inherit lib; } {
    definitions = cfg.definitions;
    domain = cfg.domain;
    serviceUrl = servicesLib.serviceUrl cfg;
  };
  credentialsDir = "/run/credentials/authelia-main.service";
  secretNames = {
    JWT_SECRET = "jwtSecret";
    OIDC_HMAC_SECRET = "oidcHmacSecret";
    OIDC_JWKS_KEY = "oidcJwksKey";
    SESSION_SECRET = "sessionSecret";
    SMTP_PASSWORD = "smtpPassword";
    STORAGE_ENCRYPTION_KEY = "storageEncryptionKey";
  };
  secretBindMounts = lib.mapAttrs' (
    credential: secret:
    lib.nameValuePair "/run/secrets/authelia/${credential}" {
      hostPath = config.sops.secrets."authelia/${secret}".path;
      isReadOnly = true;
    }
  ) secretNames;
in
{
  sops.secrets = lib.mapAttrs' (
    _: secret:
    lib.nameValuePair "authelia/${secret}" {
      sopsFile = ../../secrets/authelia.yaml;
      owner = "root";
      mode = "0400";
    }
  ) secretNames;

  modules.services.definitions.authelia = {
    hostname = "auth";
    containerAddress = "10.231.136.7";
    port = 9091;
    auth = "bypass";
    backup.path = "${cfg.configDir}/authelia";
    monitor = true;
  };

  containers.authelia = servicesLib.mkContainer {
    inherit cfg;
    name = "authelia";
    privateUsers = "identity";
    bindMounts = {
      "/config" = {
        hostPath = "${cfg.configDir}/authelia/config";
        isReadOnly = false;
      };
      "/secrets" = {
        hostPath = "${cfg.configDir}/authelia/secrets";
        isReadOnly = true;
      };
    }
    // secretBindMounts;
    extraConfig = {
      networking.firewall.allowedTCPPorts = [ service.port ];

      services.authelia.instances.main = {
        enable = true;
        secrets = {
          jwtSecretFile = "${credentialsDir}/JWT_SECRET";
          storageEncryptionKeyFile = "${credentialsDir}/STORAGE_ENCRYPTION_KEY";
          sessionSecretFile = "${credentialsDir}/SESSION_SECRET";
          oidcIssuerPrivateKeyFile = "${credentialsDir}/OIDC_JWKS_KEY";
          oidcHmacSecretFile = "${credentialsDir}/OIDC_HMAC_SECRET";
        };
        settings = {
          theme = "dark";
          server = {
            address = "tcp://:${toString service.port}";
            endpoints.authz = {
              auth-request.implementation = "AuthRequest";
              forward-auth = {
                implementation = "ForwardAuth";
                authn_strategies = [
                  {
                    name = "HeaderAuthorization";
                    schemes = [ "Basic" ];
                    scheme_basic_cache_lifespan = 0;
                  }
                  { name = "CookieSession"; }
                ];
              };
            };
          };
          log.level = "info";
          totp.issuer = cfg.domain;
          webauthn = {
            enable_passkey_login = true;
            display_name = "repparw";
          };
          authentication_backend.file.path = "/config/users_database.yml";
          access_control = ingressPolicy.authelia;
          identity_providers.oidc = {
            clients = [
              {
                client_id = "home-assistant";
                client_name = "Home Assistant";
                client_secret = "$pbkdf2-sha512$310000$WJc9q4Smq9U639kDDrzuiA$Lk6O1.q7W3xKvUQw68o22eTxtasU3aN0MeRnSZ1pXludOzzF1b0CNDqG4XoH8sP8.25vVP3xq0MGfhihBWj33A";
                public = false;
                require_pkce = true;
                pkce_challenge_method = "S256";
                authorization_policy = "two_factor";
                redirect_uris = [ "https://home.${cfg.domain}/auth/oidc/callback" ];
                scopes = [
                  "openid"
                  "profile"
                  "groups"
                ];
                id_token_signed_response_alg = "RS256";
                token_endpoint_auth_method = "client_secret_post";
              }
              {
                client_id = "karakeep";
                client_name = "karakeep";
                client_secret = "$pbkdf2-sha512$310000$2iDyBWk9POMtd9zWN3UeYw$XN9N5Uhbj4MiLP4wGk98a2jy/A4P6nz5VfMPs73rgZZwn0NVjBMRJcfDXnuwhyNdMAWn/ihj2JLRuk.49EsHJg";
                public = false;
                authorization_policy = "two_factor";
                require_pkce = false;
                pkce_challenge_method = "";
                redirect_uris = [ "https://karakeep.${cfg.domain}/api/auth/callback/custom" ];
                scopes = [
                  "openid"
                  "profile"
                  "email"
                ];
                response_types = [ "code" ];
                grant_types = [ "authorization_code" ];
                access_token_signed_response_alg = "none";
                userinfo_signed_response_alg = "none";
                token_endpoint_auth_method = "client_secret_basic";
              }
            ];
            cors = {
              endpoints = [
                "authorization"
                "token"
                "revocation"
                "introspection"
              ];
              allowed_origins = [
                "https://*.${cfg.domain}"
                "https://${cfg.domain}"
              ];
            };
          };
          session = {
            name = "authelia_session";
            expiration = 3600;
            inactivity = 7200;
            cookies = [
              {
                domain = cfg.domain;
                authelia_url = authUrl;
                default_redirection_url = "https://${cfg.domain}";
              }
            ];
            redis = {
              host = "localhost";
              port = 6379;
            };
          };
          regulation = {
            max_retries = 5;
            find_time = "2m";
            ban_time = "10m";
          };
          storage.local.path = "/config/db.sqlite3";
          notifier = {
            disable_startup_check = true;
            smtp = {
              address = "submission://smtp.gmail.com:587";
              username = "ubritos@gmail.com";
              password = "_file:${credentialsDir}/SMTP_PASSWORD";
              sender = "repparw <ubritos@gmail.com>";
            };
          };
        };
      };

      systemd.services.authelia-main.serviceConfig = {
        LoadCredential = lib.mapAttrsToList (
          credential: _: "${credential}:/run/secrets/authelia/${credential}"
        ) secretNames;
        ProtectSystem = lib.mkForce "full";
      };

      services.redis.servers.authelia = {
        enable = true;
        bind = "127.0.0.1";
        port = 6379;
      };

    };
  };
}
