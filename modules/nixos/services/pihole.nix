{ cfg, ... }:
{
  "pihole" = {
    image = "docker.io/pihole/pihole:latest";
    environment = {
      "TZ" = cfg.timezone;
    };
    labels = {
      "traefik.enable" = "false"; # TODO remove when combining with moque
    };
    volumes = [
      "${cfg.configDir}/pihole/etc:/etc/pihole"
      "${cfg.configDir}/pihole/dnsmasq.d:/etc/dnsmasq.d"
    ];
    ports = [
      "53:53/tcp"
      "53:53/udp"
    ];
    # extraOptions = [ TODO healthcheck
    #   "--device=/dev/dri:/dev/dri:rwm"
    #   "--health-cmd=curl -f http://localhost:8096/health || exit 1"
    # ];
  };
}
