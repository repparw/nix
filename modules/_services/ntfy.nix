{ cfg, lib, ... }:
{
  containers.ntfy = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = 34000;
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.11";
    bindMounts = {
      "/var/lib/ntfy-sh" = {
        hostPath = "${cfg.configDir}/ntfy";
        isReadOnly = false;
      };
    };
    config =
      { ... }:
      {
        networking.firewall.allowedTCPPorts = [ 8090 ];
        networking.useHostResolvConf = false;
        networking.nameservers = [ "10.231.136.1" ];

        services.ntfy-sh = {
          enable = true;
          settings = {
            base-url = "https://ntfy.${cfg.domain}";
            listen-http = ":8090";
            cache-file = "/var/lib/ntfy-sh/cache.db";
            auth-file = "/var/lib/ntfy-sh/auth.db";
            auth-default-access = "deny-all";
            behind-proxy = true;
            attachment-cache-dir = "/var/lib/ntfy-sh/attachments";
            enable-login = true;
          };
        };
        systemd.services.ntfy-sh = {
          serviceConfig = {
            DynamicUser = lib.mkForce false;
            StateDirectory = lib.mkForce "";
          };
        };
        users.users.ntfy-sh = {
          isSystemUser = true;
          group = "ntfy-sh";
        };
        users.groups.ntfy-sh = { };
        system.stateVersion = "26.05";
      };
  };

  systemd.services."container@ntfy".preStart = "chown -R 34998:34998 ${cfg.configDir}/ntfy";
}
