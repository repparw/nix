{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.services;
  servicesLib = import ./lib.nix { inherit lib pkgs; };
  service = cfg.definitions.authelia;
  authUrl = "https://${service.hostname}.${cfg.domain}";
  ingressPolicy = import ./ingress-policy.nix { inherit lib; } {
    definitions = cfg.definitions;
    domain = cfg.domain;
    serviceUrl = name: servicesLib.serviceUrl cfg config name;
  };
  credentialsDir = "/run/credentials/authelia-main.service";
  # pnpm 12.9 changed the dependency output: nixpkgs issue #571789.
  # Only repair the known aarch64 hash; a corrected upstream hash retires this.
  autheliaPackage =
    if
      pkgs.stdenv.hostPlatform.system == "aarch64-linux"
      && pkgs.authelia.version == "4.39.28"
      && pkgs.authelia.web.pnpmDeps.outputHash == "sha256-B/Au9YICuRM6+J4DojFbXf2IEWC+j1jRsU68nn08Puk="
    then
      pkgs.authelia.override {
        authelia-web = pkgs.authelia.web.overrideAttrs (old: {
          pnpmDeps = old.pnpmDeps.overrideAttrs {
            outputHash = "sha256-YUInqRclRdnMzxfJKuVdXwKaRzJd9sFu16dxCAgVJI8=";
          };
        });
      }
    else
      pkgs.authelia;
  secretNames = {
    JWT_SECRET = "jwtSecret";
    OIDC_HMAC_SECRET = "oidcHmacSecret";
    OIDC_JWKS_KEY = "oidcJwksKey";
    SESSION_SECRET = "sessionSecret";
    SMTP_PASSWORD = "smtpPassword";
    STORAGE_ENCRYPTION_KEY = "storageEncryptionKey";
  };
  secretBindMounts =
    lib.mapAttrs' (
      credential: secret:
      lib.nameValuePair "/run/secrets/authelia/${credential}" {
        hostPath = config.sops.secrets."authelia/${secret}".path;
        isReadOnly = true;
      }
    ) secretNames
    // {
      "/run/secrets/authelia/USERS_DATABASE" = {
        hostPath = config.sops.secrets.autheliaUsersDatabase.path;
        isReadOnly = true;
      };
    };
in
{
  # The host directory is the security boundary for mutable Authelia state.
  # Secrets themselves are projected read-only from sops-nix below; keep
  # password hashes and the SQLite auth/session state inaccessible to other
  # host users even when Authelia creates them with a permissive umask.
  systemd.tmpfiles.rules = [
    "d ${cfg.configDir}/authelia 0700 999 999 - -"
    "d ${cfg.configDir}/authelia/config 0700 999 999 - -"
  ];

  sops.secrets =
    lib.mapAttrs' (
      _: secret:
      lib.nameValuePair "authelia/${secret}" {
        sopsFile = ../../secrets/authelia.sops.yaml;
        owner = "root";
        mode = "0400";
      }
    ) secretNames
    // {
      autheliaUsersDatabase = {
        sopsFile = ../../secrets/authelia-users.sops.yaml;
        key = "usersDatabase";
        owner = "root";
        mode = "0400";
      };
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
    }
    // secretBindMounts;
    extraConfig = {
      networking.firewall.allowedTCPPorts = [ service.port ];

      services.authelia.instances.main = {
        enable = true;
        package = autheliaPackage;
        secrets = {
          jwtSecretFile = "/run/secrets/authelia/JWT_SECRET";
          storageEncryptionKeyFile = "/run/secrets/authelia/STORAGE_ENCRYPTION_KEY";
          sessionSecretFile = "/run/secrets/authelia/SESSION_SECRET";
          oidcIssuerPrivateKeyFile = "/run/secrets/authelia/OIDC_JWKS_KEY";
          oidcHmacSecretFile = "/run/secrets/authelia/OIDC_HMAC_SECRET";
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
        LoadCredential = [
          "SMTP_PASSWORD:/run/secrets/authelia/SMTP_PASSWORD"
          "INITIAL_USERS_DATABASE:/run/secrets/authelia/USERS_DATABASE"
        ];
        # "+" runs this as root before the User= drop, so it applies
        # inside the container's 1:1 userns to the host-side directory.
        ExecStartPre = [
          "+${pkgs.coreutils}/bin/chown -R 999:999 /config"
          "+${pkgs.writeShellScript "authelia-seed-users-database" ''
            if [ ! -e /config/users_database.yml ]; then
              ${pkgs.coreutils}/bin/install --owner=999 --group=999 --mode=0600 ${credentialsDir}/INITIAL_USERS_DATABASE /config/users_database.yml
            fi
          ''}"
        ];
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
