{ cfg, ... }:
{
  "dozzle" = {
    image = "docker.io/amir20/dozzle:latest";
    environment = {
      "TZ" = cfg.timezone;
    };
    volumes = [
      "/run/user/1000/podman/podman.sock:/var/run/docker.sock"
      "${cfg.configDir}/dozzle:/data"
    ];
    labels = {
      "traefik.http.routers.dozzle.rule" = "Host(`logs.${cfg.domain}`)";
      "traefik.http.services.dozzle.loadbalancer.server.port" = "8080";
    };
  };
}
