{
  cfg,
  config,
  lib,
  ...
}:
{
  containers.freshrss = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.9";
    bindMounts = {
      "/config" = {
        hostPath = "${cfg.configDir}/freshrss";
        isReadOnly = false;
      };
    };
    config =
      { ... }:
      {
        services.freshrss = {
          enable = true;
          baseUrl = "https://rss.${cfg.domain}";
          dataDir = "/config";
          defaultUser = "admin";
          authType = "none";
          webserver = "nginx";
          virtualHost = "rss.${cfg.domain}";
        };

        services.nginx.virtualHosts."rss.${cfg.domain}".listen = [
          {
            addr = "0.0.0.0";
            port = 8082;
          }
        ];

        system.stateVersion = "26.05";
      };
  };

  systemd.services."container@freshrss".serviceConfig.EnvironmentFile =
    config.sops.secrets.freshrss.path;
}
