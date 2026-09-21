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
        # Host-decrypted state dir for the container bind mount. Owned by the
        # mapped container user (see privateUsers below), not root: the
        # module's in-container tmpfiles cannot chown across an unmapped
        # mount, and Django refuses to start when PAPERLESS_DATA_DIR is not
        # writeable (boot loops forever, nspawn never signals READY).
        systemd.tmpfiles.rules = [
          "d ${cfg.configDir}/paper 0755 393531 393531 -"
        ];

        # First boot on slow storage can spend minutes in the scheduler
        # preStart (Django migrate + Tantivy reindex) before nspawn sees
        # READY. The default 60s start timeout kills the container mid-boot
        # and restart-loops forever without ever converging.
        systemd.services."container@paperless".serviceConfig.TimeoutStartSec = lib.mkForce "10min";

        containers.paperless = servicesLib.mkContainer {
          inherit cfg;
          name = "paperless";
          # User namespace: container uid 0 -> host 393216 (= 6 x 65536,
          # systemd's upper-16-bit recommendation). Deterministic instead of
          # `pick` so the state-dir ownership above stays valid across
          # reboots; `pick` ranges are not guaranteed stable and a re-pick
          # silently revokes the container user's write access to its own
          # data dir (Django system check fails, boot loops, no READY).
          # Container paperless (315) becomes host 393531.
          # ONE-TIME MIGRATION: existing files under configDir/paper must be
          # chowned once on the host:
          #   sudo chown -R 393531:393531 /home/containers/config/paper
          privateUsers = 393216;
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
