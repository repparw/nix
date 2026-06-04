{
  cfg,
  config,
  lib,
  ...
}:
{
  # sops-nix template: rendered at activation to /run/secrets/miniflux-env,
  # bind-mounted read-only into the container, and loaded as EnvironmentFile
  # by the miniflux systemd unit. Keeps OIDC_CLIENT_SECRET out of the Nix store.
  #
  # TODO before first deploy:
  #   Add minifluxOidcSecret to secrets.yaml with plaintext value:
  #     evep2ip3jvsMZCitukKs+rgQYp1tspWljFIpnEpq2Mg=
  #   Encrypt with: sops secrets.yaml
  #   The PBKDF2 hash in authelia.nix was generated from this value.
  sops.templates."miniflux-env" = {
    path = "/run/secrets/miniflux-env";
    owner = "root";
    # World-readable: bind-mounted into a userns container (privateUsers=pick),
    # so the container's mapped root cannot read a 0400 file owned by host root.
    # The /run/secrets directory itself is 0700, so this only widens access
    # for processes already inside the container.
    mode = "0444";
    content = ''
      OIDC_CLIENT_ID=4c06b7fb-8078-eb7f-67b4-713dcf3479e5
      OIDC_CLIENT_SECRET=${config.sops.placeholder.minifluxOidcSecret}
      OIDC_REDIRECT_URL=https://rss.${cfg.domain}/oauth2/callback
      OIDC_PROVIDER=https://auth.${cfg.domain}
      OIDC_PROVIDER_NAME=Authelia
    '';
  };

  containers.miniflux = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.9";
    bindMounts = {
      "/var/lib/postgresql" = {
        hostPath = "${cfg.configDir}/miniflux/db";
        isReadOnly = false;
      };
      "/run/secrets/miniflux-env" = {
        hostPath = config.sops.templates."miniflux-env".path;
        isReadOnly = true;
      };
    };
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
          };
        };

        systemd.services.miniflux.serviceConfig.EnvironmentFile = "/run/secrets/miniflux-env";

        system.stateVersion = "26.05";
      };
  };

  systemd.services."container@miniflux".preStart =
    "mkdir -p ${cfg.configDir}/miniflux/db && chmod 0700 ${cfg.configDir}/miniflux/db";
}
