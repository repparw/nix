{ cfg, lib, ... }:
{
  containers.changedetection = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.8";
    bindMounts = {
      "/config" = {
        hostPath = "${cfg.configDir}/changedetection";
        isReadOnly = false;
      };
    };
    config =
      { ... }:
      {
        nixpkgs.config.allowUnfree = true;

        services.changedetection-io = {
          enable = true;
          playwrightSupport = true;
          port = 5000;
          baseURL = "https://changedetection.${cfg.domain}";
          behindProxy = true;
          datastorePath = "/config";
        };
        system.stateVersion = "26.05";
      };
  };
}
