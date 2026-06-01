{
  cfg,
  config,
  lib,
  pkgs,
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
        networking.firewall.allowedTCPPorts = [ 8082 ];
        networking.useHostResolvConf = false;
        networking.nameservers = [ "10.231.136.1" ];

        services.freshrss = {
          enable = true;
          baseUrl = "https://rss.${cfg.domain}";
          dataDir = "/config";
          defaultUser = "repparw";
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

        systemd.services.mercury-parser-api = {
          description = "Mercury Parser API";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.mercury-parser-api}/bin/mercury-parser-api";
            Restart = "on-failure";
            Type = "simple";
          };
        };

        environment.systemPackages = [ pkgs.mercury-parser-api ];

        system.stateVersion = "26.05";
      };
  };

  systemd.services."container@freshrss".serviceConfig.EnvironmentFile = lib.mkForce [
    "-/etc/nixos-containers/freshrss.conf"
    config.sops.secrets.freshrss.path
  ];
}
