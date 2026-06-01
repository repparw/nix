{ cfg, ... }:
{
  containers.paperless = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.12";
    bindMounts = {
      "/data" = {
        hostPath = "${cfg.dataDir}/paper/data";
        isReadOnly = false;
      };
      "/media" = {
        hostPath = "${cfg.dataDir}/paper/media";
        isReadOnly = false;
      };
      "/consume" = {
        hostPath = "${cfg.dataDir}/paper/consume";
        isReadOnly = false;
      };
    };
    config =
      { ... }:
      {
        services.paperless = {
          enable = true;
          dataDir = "/data";
          mediaDir = "/media";
          consumptionDir = "/consume";
          port = 8000;
          address = "0.0.0.0";
          settings = {
            PAPERLESS_OCR_LANGUAGE = "spa";
            PAPERLESS_ENABLE_HTTP_REMOTE_USER = "true";
            PAPERLESS_HTTP_REMOTE_USER_HEADER_NAME = "HTTP_REMOTE_USER";
            PAPERLESS_LOGOUT_REDIRECT_URL = "https://auth.${cfg.domain}/logout";
            PAPERLESS_URL = "https://paper.${cfg.domain}";
            PAPERLESS_DISABLE_REGULAR_LOGIN = "1";
          };
        };
        system.stateVersion = "26.05";
      };
  };
}
