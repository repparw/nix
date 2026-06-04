{
  cfg,
  config,
  lib,
  ...
}:
{
  containers.miniflux = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.9";
    # Bind mount via extraFlags so we can add :idmap, required for the
    # container userns root to read files owned by host root.
    extraFlags = [
      "--bind-ro=${config.sops.secrets.minifluxOidcSecret.path}:/run/secrets/minifluxOidcSecret:idmap"
    ];
    bindMounts = { };
    config =
      { ... }:
      {
        networking.useHostResolvConf = false;
        networking.nameservers = [ "10.231.136.1" ];
        networking.firewall.allowedTCPPorts = [ 8080 ];

        services.miniflux = {
          enable = true;
          config = {
            BASE_URL = "https://rss.${cfg.domain}";
            LISTEN_ADDR = "0.0.0.0:8080";
            CREATE_ADMIN = 0;
            RUN_MIGRATIONS = 1;
            CLEANUP_FREQUENCY_HOURS = 24;
            OIDC_CLIENT_ID = "4c06b7fb-8078-eb7f-67b4-713dcf3479e5";
            OIDC_CLIENT_SECRET_FILE = "/run/secrets/minifluxOidcSecret";
            OIDC_REDIRECT_URL = "https://rss.${cfg.domain}/oauth2/callback";
            OIDC_PROVIDER = "https://auth.${cfg.domain}";
            OIDC_PROVIDER_NAME = "Authelia";
          };
        };

        system.stateVersion = "26.05";
      };
  };
}
