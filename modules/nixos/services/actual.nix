{ cfg, ... }:
{
  "actual" = {
    image = "docker.io/actualbudget/actual-server:latest";
    volumes = [
      "${cfg.configDir}/actual:/data"
    ];
    extraOptions = [
      "--health-cmd=node src/scripts/health-check.js"
      "--health-interval=60s"
      "--health-timeout=10s"
      "--health-retries=3"
      "--health-start-period=20s"
    ];
    labels = {
      # "traefik.http.services.actual.loadbalancer.server.port" = "5006";
    };
  };
}
