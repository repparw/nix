{ cfg, ... }:
{
  "hermes" = {
    image = "docker.io/nousresearch/hermes-agent:latest";
    environment = {
      "HERMES_HOME" = "/opt/data";
      "HERMES_UID" = cfg.user;
      "HERMES_GID" = cfg.group;
      "TZ" = cfg.timezone;
      "PYTHONUNBUFFERED" = "1";
    };
    volumes = [
      "${cfg.configDir}/hermes:/opt/data"
    ];
    cmd = [ "gateway" ];
    extraOptions = [
      "--init"
    ];
    labels = {
      "traefik.enable" = "false";
      "glance.hide" = "true";
    };
  };
}
