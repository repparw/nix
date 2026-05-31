{ cfg, lib, ... }:
{
  containers.grafana = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.13";
    config =
      { ... }:
      {
        services.grafana = {
          enable = true;
          settings = {
            server = {
              http_addr = "0.0.0.0";
              http_port = 3000;
              domain = "grafana.${cfg.domain}";
              root_url = "https://grafana.${cfg.domain}";
            };
            security = {
              admin_user = "admin";
              admin_password = "";
              secret_key = "SW2YcwTIb9zpOOhoPsMm";
            };
          };
        };
        system.stateVersion = "26.05";
      };
  };
}
