{ cfg, ... }:
{
  containers.paperless = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.12";
    extraFlags = [
      "--bind=${cfg.dataDir}/paper/data:/data"
      "--bind=${cfg.dataDir}/paper/media:/media"
      "--bind=${cfg.dataDir}/paper/consume:/consume"
    ];
    bindMounts = { };
    config =
      { ... }:
      {
        networking.firewall.allowedTCPPorts = [ 8000 ];
        networking.useHostResolvConf = false;
        networking.nameservers = [ "10.231.136.1" ];

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
