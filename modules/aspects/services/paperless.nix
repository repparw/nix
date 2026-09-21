{ den, ... }:
{
  den.aspects.nixos-services.provides.paperless = {
    service-registry = {
      name = "paperless";
      definition = {
        hostname = "paper";
        port = 8000;
        auth = "one_factor";
        container = true;
        monitor = true;
        backupRelativePath = "paperless/export";
      };
    };

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.modules.services;
        servicesLib = import ../../_services/lib.nix { inherit lib pkgs; };
        service = cfg.definitions.paperless;
      in
      {
        systemd.tmpfiles.rules = [
          "d ${cfg.configDir}/paper 0755 root root -"
        ];

        # First boot on slow storage can spend minutes in the scheduler
        # preStart (Django migrate + Tantivy reindex) before nspawn sees
        # READY. The default 60s start timeout kills the container mid-boot
        # and restart-loops forever without ever converging.
        systemd.services."container@paperless".serviceConfig.TimeoutStartSec = lib.mkForce "10min";

        containers.paperless = servicesLib.mkContainer {
          inherit cfg;
          name = "paperless";
          privateUsers = "pick";
          forwardPorts = [
            {
              protocol = "tcp";
              hostPort = 8000;
              containerPort = 8000;
            }
          ];
          bindMounts = {
            "/var/lib/paperless" = {
              hostPath = "${cfg.configDir}/paper";
              isReadOnly = false;
            };
          };
          extraConfig = {
            networking.firewall.allowedTCPPorts = [ service.port ];

            services.paperless = {
              enable = true;
              port = service.port;
              address = "0.0.0.0";
              exporter = {
                enable = true;
                onCalendar = "*-*-7,14,21,28 03:45:00";
                settings = {
                  "no-archive" = true;
                  "no-thumbnail" = true;
                };
              };
              settings = {
                PAPERLESS_ENABLE_HTTP_REMOTE_USER = "true";
                PAPERLESS_HTTP_REMOTE_USER_HEADER_NAME = "HTTP_REMOTE_USER";
                PAPERLESS_LOGOUT_REDIRECT_URL = "https://auth.${cfg.domain}/logout";
                PAPERLESS_URL = "https://${service.hostname}.${cfg.domain}";
                PAPERLESS_DISABLE_REGULAR_LOGIN = "1";
              };
            };
          };
        };
      };
  };
}
