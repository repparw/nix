{
  cfg,
  lib,
  pkgs,
  ...
}:
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

        networking.firewall.allowedTCPPorts = [ 5000 ];
        networking.useHostResolvConf = false;
        networking.nameservers = [ "10.231.136.1" ];

        environment.systemPackages = [ pkgs.playwright.browsers ];

        services.changedetection-io = {
          enable = true;
          playwrightSupport = false;
          listenAddress = "0.0.0.0";
          port = 5000;
          baseURL = "https://changedetection.${cfg.domain}";
          behindProxy = true;
          datastorePath = "/config";
        };
        systemd.services.changedetection-io.serviceConfig.Environment = lib.mkForce [
          "HIDE_REFERER=true"
          "BASE_URL=https://changedetection.${cfg.domain}"
          "USE_X_SETTINGS=1"
          "PLAYWRIGHT_DRIVER_URL=ws://127.0.0.1:3000/?stealth=1&--disable-web-security=true"
        ];
        systemd.services.changedetection-io.after = lib.mkAfter [ "changedetection-chromium.service" ];
        systemd.services.changedetection-io.wants = [ "changedetection-chromium.service" ];

        systemd.services.changedetection-chromium = {
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            ExecStart = lib.concatStringsSep " " [
              "${pkgs.playwright.browsers}/chromium_headless_shell-1217/chrome-headless-shell-linux64/chrome-headless-shell"
              "--no-sandbox"
              "--disable-gpu"
              "--disable-dev-shm-usage"
              "--user-data-dir=/config/chromium"
              "--remote-debugging-port=3000"
              "--remote-debugging-address=127.0.0.1"
              "about:blank"
            ];
            Restart = "always";
            RestartSec = "5s";
            User = "changedetection-io";
            Group = "changedetection-io";
          };
        };

        system.stateVersion = "26.05";
      };
  };
}
