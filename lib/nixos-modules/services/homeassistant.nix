{ cfg, ... }:
{
  "homeassistant" = {
    image = "docker.io/home-assistant/home-assistant:latest";
    environment = {
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.configDir}/hass:/config"
      "/etc/localtime:/etc/localtime:ro"
      "/run/dbus:/run/dbus:ro"
    ];
    privileged = true;
    # extraOptions = [ TODO healthcheck
    #   "--device=/dev/dri:/dev/dri:rwm"
    #   "--health-cmd=curl -f http://localhost:8096/health || exit 1"
    # ];
    labels = {
      "traefik.http.routers.homeassistant.rule" = "Host(`${cfg.domain}`)"; # remove when combining
      "traefik.http.routers.homeassistant.tls.certResolver" = "cloudflare"; # remove when combining
    };
  };
}
