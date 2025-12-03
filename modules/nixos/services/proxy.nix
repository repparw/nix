{ cfg, config, ... }:
{
  "traefik" = {
    image = "docker.io/library/traefik:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
    };
    environmentFiles = [
      config.age.secrets.cloudflare.path
    ];
    volumes = [
      "${cfg.configDir}/traefik:/config"
      "/run/podman/podman.sock:/var/run/docker.sock"
    ];
    cmd = [
      "--configFile=/config/traefik.yml"
    ];
    ports = [
      # "8080:8080/tcp"
      "443:443/tcp"
    ];
    labels = {
      "glance.hide" = "true";
      "traefik.tls.stores.default.defaultgeneratedcert.resolver" = "cloudflare";
      "traefik.tls.stores.default.defaultgeneratedcert.domain.main" = "${cfg.domain}";
      "traefik.tls.stores.default.defaultgeneratedcert.domain.sans" = "*.${cfg.domain}";
      # auth middleware
      # defined here as authelia can start after traefik
      "traefik.http.middlewares.authelia.forwardAuth.address" =
        "http://authelia:9091/api/authz/forward-auth";
      "traefik.http.middlewares.authelia.forwardAuth.trustForwardHeader" = "true";
      "traefik.http.middlewares.authelia.forwardAuth.authResponseHeaders" =
        "Remote-User,Remote-Groups,Remote-Email,Remote-Name";
    };
  };
  "ddclient" = {
    image = "docker.io/linuxserver/ddclient:latest";
    environment = {
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.configDir}/ddclient:/config"
    ];
    extraOptions = [
      "--health-cmd=pgrep ddclient || exit 1"
    ];
    labels = {
      "glance.parent" = "traefik";
      "traefik.enable" = "false";
    };
  };
  "glance" = {
    image = "docker.io/glanceapp/glance:latest";
    volumes = [
      "${cfg.configDir}/glance:/app/config"
      "/run/podman/podman.sock:/var/run/docker.sock"
    ];
    labels = {
      "glance.parent" = "traefik";
      "traefik.http.routers.glance.rule" = "Host(`${cfg.domain}`)";
      "traefik.http.routers.glance.tls.certResolver" = "cloudflare";
    };
  };
}
