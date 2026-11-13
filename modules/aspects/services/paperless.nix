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
        backupRelativePath = "paper/export";
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
          "d ${cfg.configDir}/paper 0755 393531 393531 -"
          "z ${cfg.configDir}/paper 0755 393531 393531 -"
        ];

        # First boot on slow storage can spend minutes in the scheduler
        # preStart (Django migrate + Tantivy reindex) before nspawn sees
        # READY. The default 60s start timeout kills the container mid-boot
        # and restart-loops forever without ever converging.
        systemd.services."container@paperless".serviceConfig.TimeoutStartSec = lib.mkForce "10min";

        containers.paperless = servicesLib.mkContainer {
          inherit cfg;
          name = "paperless";
          privateUsers = 393216;
          bindMounts = {
            "/var/lib/paperless" = {
              hostPath = "${cfg.configDir}/paper";
              isReadOnly = false;
            };
          };
          extraConfig = {
            networking.firewall.allowedTCPPorts = [ service.port ];
            # The host copies resolv.conf as host root before nspawn starts.
            # A fixed user namespace cannot update that unmapped file.
            services.resolved.enable = true;

            services.paperless = {
              enable = true;
              port = service.port;
              address = "0.0.0.0";
              exporter = {
                enable = true;
                onCalendar = null;
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
