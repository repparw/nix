{ cfg, ... }:
{
  containers.authelia = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.7";
    bindMounts = {
      "/config" = {
        hostPath = "${cfg.configDir}/authelia/config";
        isReadOnly = false;
      };
      "/secrets" = {
        hostPath = "/home/containers/config/authelia/secrets";
        isReadOnly = true;
      };
    };
    config =
      { ... }:
      {
        networking.firewall.allowedTCPPorts = [ 9091 ];
        networking.useHostResolvConf = false;
        networking.nameservers = [ "10.231.136.1" ];

        services.authelia.instances.main = {
          enable = true;
          secrets = {
            jwtSecretFile = "/secrets/JWT_SECRET";
            storageEncryptionKeyFile = "/secrets/STORAGE_ENCRYPTION_KEY";
            sessionSecretFile = "/secrets/SESSION_SECRET";
            oidcIssuerPrivateKeyFile = "/secrets/OIDC_JWKS_KEY";
            oidcHmacSecretFile = "/secrets/OIDC_HMAC_SECRET";
          };
          settings = {
            theme = "dark";
            server = {
              address = "tcp://:9091";
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
            access_control = {
              default_policy = "deny";
              rules = [
                {
                  domain = [
                    "auth.${cfg.domain}"
                  ];
                  policy = "bypass";
                }
                {
                  domain = [ "auth.${cfg.domain}" ];
                  policy = "bypass";
                }
                {
                  domain = [ "paper.${cfg.domain}" ];
                  resources = [ "^/share/.*$" ];
                  policy = "bypass";
                }
                {
                  domain = [ "ntfy.${cfg.domain}" ];
                  methods = [
                    "GET"
                    "POST"
                    "PUT"
                  ];
                  resources = [
                    "^/((seerr|changedetection)|((diun|changedetection),(diun|changedetection)))([/?].*)?$"
                  ];
                  policy = "bypass";
                }
                {
                  domain = [ "ntfy.${cfg.domain}" ];
                  methods = [ "POST" ];
                  policy = "bypass";
                }
                {
                  domain = [
                    "bazarr.${cfg.domain}"
                    "changedetection.${cfg.domain}"
                    "paper.${cfg.domain}"
                    "qbit.${cfg.domain}"
                    "radarr.${cfg.domain}"
                    "rss.${cfg.domain}"
                    "sonarr.${cfg.domain}"
                  ];
                  resources = [
                    "^/api([/?].*)?$"
                    "^/v1/([/?].*)?$"
                  ];
                  policy = "bypass";
                }
                {
                  domain = [
                    "jellyfin.${cfg.domain}"
                    "home.${cfg.domain}"
                  ];
                  policy = "bypass";
                }
                {
                  domain = [ "*.${cfg.domain}" ];
                  subject = [ "group:admins" ];
                  policy = "one_factor";
                }
              ];
            };
            identity_providers.oidc = {
              clients = [
                {
                  client_id = "4c06b7fb-8078-eb7f-67b4-713dcf3479e5";
                  client_name = "Miniflux";
                  # PBKDF2-SHA512 hash of minifluxOidcSecret plaintext
                  client_secret = "$pbkdf2-sha512$310000$YA9moMJnULbN7tBa4rGglA$9Kt1uznIN.aOECEXkmHD5I.GCJNKvjhGgJIor6u4O6b9xlCQHhFTUUjTHDe7b26Uje9YxmYObjFYpVahr35MHw";
                  public = false;
                  authorization_policy = "one_factor";
                  redirect_uris = [ "https://rss.${cfg.domain}/oauth2/callback" ];
                  scopes = [
                    "openid"
                    "groups"
                    "email"
                    "profile"
                  ];
                  userinfo_signed_response_alg = "none";
                  token_endpoint_auth_method = "client_secret_basic";
                }
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
                  authelia_url = "https://auth.${cfg.domain}";
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
                password = "_file:/secrets/SMTP_PASSWORD";
                sender = "repparw <ubritos@gmail.com>";
              };
            };
          };
        };

        services.redis.servers.authelia = {
          enable = true;
          bind = "127.0.0.1";
          port = 6379;
        };

        system.stateVersion = "26.05";
      };
  };
}
