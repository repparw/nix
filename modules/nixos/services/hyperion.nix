{ cfg, ... }:
{
  "hyperion" = {
    image = "docker.io/foorschtbar/hyperion:latest";
    environment = {
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.configDir}/hyperion:/root/.hyperion"
    ];
    # extraOptions = [ TODO healthcheck
    #   "--device=/dev/dri:/dev/dri:rwm"
    #   "--health-cmd=curl -f http://localhost:8096/health || exit 1"
    # ];
    labels = {
      "traefik.enable" = "false";
    };
  };
}
