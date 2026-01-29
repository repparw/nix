{ cfg, ... }:
{
  "grafana" = {
    image = "docker.io/grafana/grafana:latest";
    volumes = [
      "${cfg.configDir}/grafana:/var/lib/grafana"
    ];
    user = "${cfg.user}:${cfg.group}";
  };
  "prometheus" = {
    image = "docker.io/prom/prometheus:latest";
    volumes = [
      "${cfg.configDir}/prometheus:/etc/prometheus"
    ];
  };
  "podman-exporter" = {
    image = "quay.io/navidys/prometheus-podman-exporter:latest";
    environment = {
      "CONTAINER_HOST" = "unix:///run/podman/podman.sock";
    };
    labels = {
      "glance.hide" = "true";
      "traefik.enable" = "false";
    };
  };
}
