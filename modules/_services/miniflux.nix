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
  # TODO: replace PLACEHOLDER values before first deploy:
  #   1. Generate a client secret:  openssl rand -base64 32
  #   2. Encrypt it under sops:     sops secrets.yaml  (add minifluxOidcSecret key)
  #   3. Put the same plaintext OIDC_CLIENT_ID here
  #   4. Use the same client_id in modules/_services/authelia.nix and PBKDF2-hash
  #      the same secret with:  authelia crypto hash generate pbkdf2 --variant sha512
  sops.templates."miniflux-env" = {
    path = "/run/secrets/miniflux-env";
    owner = "root";
    # World-readable: bind-mounted into a userns container (privateUsers),
    # so the container's mapped root (host uid 36000) cannot read a 0400
    # file owned by host root. The /run/secrets directory itself is 0700,
    # so this only widens access for processes already inside the container.
    mode = "0444";
    content = ''
      OIDC_CLIENT_ID=PLACEHOLDER_REPLACE_WITH_CLIENT_ID
      OIDC_CLIENT_SECRET=${config.sops.placeholder.minifluxOidcSecret}
      OIDC_REDIRECT_URL=https://rss.${cfg.domain}/oauth2/callback
      OIDC_PROVIDER=https://auth.${cfg.domain}
      OIDC_PROVIDER_NAME=Authelia
    '';
  };

  containers.miniflux = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = 36000;
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.9";
    bindMounts = {
      "/var/lib/miniflux" = {
        hostPath = "${cfg.configDir}/miniflux";
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
            DATABASE_URL = "file:///var/lib/miniflux/miniflux.db?cache=shared&_journal_mode=WAL";
            RUN_MIGRATIONS = 1;
            CLEANUP_FREQUENCY_HOURS = 24;
          };
        };

        systemd.services.miniflux.serviceConfig.EnvironmentFile = "/run/secrets/miniflux-env";

        system.stateVersion = "26.05";
      };
  };

  systemd.services."container@miniflux".preStart = "chown -R 36000:36000 ${cfg.configDir}/miniflux";
}
