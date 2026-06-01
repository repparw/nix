{ cfg, ... }:
{
  containers.ntfy = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.11";
    bindMounts = {
      "/etc/ntfy" = {
        hostPath = "${cfg.configDir}/ntfy";
        isReadOnly = false;
      };
    };
    config =
      { ... }:
      {
        services.ntfy-sh = {
          enable = true;
          settings = {
            base-url = "https://ntfy.${cfg.domain}";
            listen-http = ":8090";
            cache-file = "/etc/ntfy/cache.db";
            auth-file = "/etc/ntfy/auth.db";
            auth-default-access = "deny-all";
            behind-proxy = true;
            attachment-cache-dir = "/etc/ntfy/attachments";
            enable-login = true;
          };
        };
        system.stateVersion = "26.05";
      };
  };
}
