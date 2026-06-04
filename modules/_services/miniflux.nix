{
  cfg,
  config,
  lib,
  ...
}:
{
  services.miniflux = {
    enable = true;
    config = {
      BASE_URL = "https://rss.${cfg.domain}";
      LISTEN_ADDR = "0.0.0.0:8080";
      CREATE_ADMIN = 0;
      RUN_MIGRATIONS = 1;
      CLEANUP_FREQUENCY_HOURS = 24;
      OIDC_CLIENT_ID = "4c06b7fb-8078-eb7f-67b4-713dcf3479e5";
      OIDC_CLIENT_SECRET_FILE = config.sops.secrets.minifluxOidcSecret.path;
      OIDC_REDIRECT_URL = "https://rss.${cfg.domain}/oauth2/callback";
      OIDC_PROVIDER = "https://auth.${cfg.domain}";
      OIDC_PROVIDER_NAME = "Authelia";
    };
  };
}
