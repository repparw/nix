{ cfg, lib, ... }:
{
  containers.prometheus = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.14";
    config =
      { ... }:
      {
        services.prometheus = {
          enable = true;
          port = 9090;
          globalConfig = {
            scrape_interval = "15s";
            evaluation_interval = "15s";
          };
          scrapeConfigs = [
            {
              job_name = "prometheus";
              static_configs = [ { targets = [ "localhost:9090" ]; } ];
            }
            {
              job_name = "node";
              static_configs = [ { targets = [ "localhost:9100" ]; } ];
            }
          ];
        };

        services.prometheus.exporters.node = {
          enable = true;
          enabledCollectors = [
            "systemd"
            "processes"
          ];
          port = 9100;
        };

        system.stateVersion = "26.05";
      };
  };
}
