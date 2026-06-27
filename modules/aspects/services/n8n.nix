{
  den,
  lib,
  ...
}:
{
  den.aspects.nixos-services.provides.n8n = {
    nixos =
      { config, pkgs, ... }:
      let
        serviceName = "n8n";
        cfg = config.modules.services;
        service = cfg.inventory.${serviceName};
        servicesLib = import ../../_services/lib.nix { inherit lib pkgs; };
        host = "${service.hostname}.${cfg.domain}";
        baseUrl = "https://${host}";
      in
      {
        systemd.tmpfiles.rules = [
          "d ${cfg.configDir}/${serviceName} 0750 64383 64383 - -"
          "d ${cfg.configDir}/${serviceName}/workflows 0750 64383 64383 - -"
        ];

        modules.services.inventory.${serviceName} = {
          hostname = "n8n";
          containerAddress = "10.231.136.16";
          port = 5678;
          auth = "one_factor";
          backup.path = "${cfg.configDir}/${serviceName}";
          monitor = true;
        };

        containers.${serviceName} = servicesLib.mkContainer {
          inherit cfg;
          name = serviceName;
          privateUsers = "identity";
          bindMounts = {
            "/config" = {
              hostPath = "${cfg.configDir}/${serviceName}";
              isReadOnly = false;
            };
            "/run/secrets/discordWebhook" = {
              hostPath = config.sops.secrets.discordWebhook.path;
              isReadOnly = true;
            };
          };
          extraConfig = {
            networking.firewall.allowedTCPPorts = [ service.port ];

            services.n8n = {
              enable = true;
              openFirewall = true;
              package = pkgs.n8n;
              environment = {
                N8N_HOST = host;
                N8N_LISTEN_ADDRESS = "0.0.0.0";
                N8N_PORT = service.port;
                N8N_PROTOCOL = "https";
                N8N_PROXY_HOPS = 1;
                N8N_EDITOR_BASE_URL = baseUrl;
                WEBHOOK_URL = "${baseUrl}/";
                GENERIC_TIMEZONE = cfg.timezone;
                TZ = cfg.timezone;
                DISCORD_WEBHOOK_URL_FILE = "/run/secrets/discordWebhook";
                N8N_BLOCK_ENV_ACCESS_IN_NODE = "false";
                NODE_FUNCTION_ALLOW_BUILTIN = "fs";
              };
            };

            systemd.services.n8n = {
              path = [ pkgs.nodejs ];
              environment = {
                HOME = lib.mkForce "/config";
                N8N_USER_FOLDER = lib.mkForce "/config";
              };
              serviceConfig.ReadWritePaths = [ "/config" ];
            };
          };
        };
      };
  };
}
