{cfg}: {
  "swag" = {
    image = "docker.io/linuxserver/swag:latest";
    environment = {
      "DNSPLUGIN" = "cloudflare";
      "TZ" = cfg.timezone;
      "SUBDOMAINS" = "wildcard";
      "URL" = cfg.domain;
      "VALIDATION" = "dns";
    };
    volumes = [
      "${cfg.dataDir}/swag:/config:rw,Z"
      "/home/repparw/src/homepage:/config/www:rw,Z"
    ];
    ports = [
      "443:443/tcp"
    ];
    extraPodmanArgs = [
      "--add-host=host.docker.internal:host-gateway"
    ];
    addCapabilities = [
      "NET_ADMIN"
    ];
  };
  "ddclient" = {
    image = "docker.io/linuxserver/ddclient:latest";
    environment = {
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}/ddclient:/config:rw,Z"
    ];
  };
}
