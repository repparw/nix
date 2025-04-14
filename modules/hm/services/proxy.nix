{cfg}: {
  "ddclient" = {
    image = "docker.io/ddclient/ddclient:latest";
    environment = {
      "DDCLIENT_CONFIG" = "/config/ddclient.conf";
      "DDCLIENT_PID" = "/var/run/ddclient.pid";
      "TZ" = cfg.timezone;
    };
    volumes = [
      "${cfg.dataDir}/ddclient/config:/config:rw,Z"
    ];
    exec = "ddclient -foreground -daemon=0 -file /config/ddclient.conf";
  };
}
