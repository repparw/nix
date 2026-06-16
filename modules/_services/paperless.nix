{
  cfg,
  servicesLib,
  ...
}:
{
  modules.services.inventory.paperless = {
    hostname = "paper";
    containerAddress = "10.231.136.12";
    port = 8000;
    auth = "one_factor";
    backup.path = "${cfg.configDir}/paperless/export";
    monitor = true;
  };

  containers.paperless = servicesLib.mkContainer {
    inherit cfg;
    name = "paperless";
    privateUsers = "pick";
    bindMounts = {
      "/var/lib/paperless" = {
        hostPath = "${cfg.configDir}/paper";
        isReadOnly = false;
      };
    };
    extraConfig = {
      networking.firewall.allowedTCPPorts = [ 8000 ];

      services.paperless = {
        enable = true;
        port = 8000;
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
          PAPERLESS_OCR_LANGUAGE = "spa";
          PAPERLESS_ENABLE_HTTP_REMOTE_USER = "true";
          PAPERLESS_HTTP_REMOTE_USER_HEADER_NAME = "HTTP_REMOTE_USER";
          PAPERLESS_LOGOUT_REDIRECT_URL = "https://auth.${cfg.domain}/logout";
          PAPERLESS_URL = "https://paper.${cfg.domain}";
          PAPERLESS_DISABLE_REGULAR_LOGIN = "1";
        };
      };
    };
  };
}
