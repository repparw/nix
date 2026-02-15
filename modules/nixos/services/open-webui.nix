{ cfg, ... }:
{
  "open-webui" = {
    image = "ghcr.io/open-webui/open-webui:latest";
    environment = {
      "WEBUI_AUTH" = "false";
    };
    volumes = [
      "${cfg.configDir}/open-webui:/app/backend/data"
    ];
    extraOptions = [
      "--health-cmd=curl -f http://localhost:8080/ || exit 1"
    ];
    labels = {
      "traefik.http.routers.open-webui.rule" = "Host(`chat.${cfg.domain}`)";
    };
  };
}
