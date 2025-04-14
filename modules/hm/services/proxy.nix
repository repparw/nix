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
    ];
    ports = [
      "8080:80/tcp"
      "8443:443/tcp"
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
