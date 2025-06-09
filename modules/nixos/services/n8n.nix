{ cfg, ... }:
{
  "n8n" = {
    image = "docker.io/n8nio/n8n:latest";
    environment = {
      "N8N_HOST" = "n8n.${cfg.domain}";
      "N8N_PORT" = "5678";
      "N8N_RUNNERS_ENABLED" = "true";
      "NODE_ENV" = "production";
      "WEBHOOK_URL" = "https://n8n.${cfg.domain}";
      "GENERIC_TIMEZONE" = cfg.timezone;
    };
    volumes = [
      "${cfg.configDir}/n8n:/home/node/.n8n"
    ];
  };
}
