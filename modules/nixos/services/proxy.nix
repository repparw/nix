{ cfg }:
{
  "swag" = {
    image = "docker.io/linuxserver/swag:latest";
    environment = {
      "DNSPLUGIN" = "cloudflare";
      "PUID" = cfg.user;
      "PGID" = cfg.group;
      "TZ" = cfg.timezone;
      "SUBDOMAINS" = "wildcard";
      "URL" = cfg.domain;
      "VALIDATION" = "dns";
    };
    volumes = [
      "${cfg.configDir}/swag:/config"
    ];
    ports = [
      "80:80/tcp"
      "443:443/tcp"
    ];
    capabilities = {
      NET_ADMIN = true;
    };
    dependsOn = [
      "glance"
    ];
    labels = {
      "glance.id" = "swag";
      "glance.hide" = "true";
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
      "glance.parent" = "swag";
    };
  };
  "glance" = {
    image = "docker.io/glanceapp/glance:latest";
    volumes = [
      "${cfg.configDir}/glance:/app/config"
      "/run/podman/podman.sock:/var/run/docker.sock"
    ];
    labels = {
      "glance.parent" = "swag";
    };
  };
}
