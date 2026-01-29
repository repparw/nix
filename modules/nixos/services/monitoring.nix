{ cfg, ... }:
{
  "grafana" = {
    image = "docker.io/grafana/grafana:latest";
    volumes = [
      "${cfg.dataDir}/grafana:/var/lib/grafana"
    ];
  };
  "prometheus" = {
    image = "docker.io/prom/prometheus:latest";
    volumes = [
      "${cfg.configDir}/prometheus:/etc/prometheus"
    ];
  };
  "node-exporter" = {
    image = "docker.io/prom/node-exporter:latest";
    extraOptions = [
      "--pid=host"
    ];
    cmd = [
      "--path.rootfs=/host"
    ];
    volumes = [
      "/:/host:ro,rslave"
    ];
    labels = {
      "glance.hide" = "true";
      "traefik.enable" = "false";
    };
  };
}
