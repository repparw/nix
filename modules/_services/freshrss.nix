{ cfg, config, ... }:
{
  "freshrss" = {
    image = "docker.io/linuxserver/freshrss:latest";
    environment = {
      "PUID" = "1000";
      "PGID" = "1000";
      "TZ" = cfg.timezone;
      "OIDC_ENABLED" = "1";
      "OIDC_PROVIDER_METADATA_URL" = "https://auth.${cfg.domain}/.well-known/openid-configuration";
      "OIDC_REMOTE_USER_CLAIM" = "preferred_username";
      "OIDC_SCOPES" = "openid groups email profile";
      "OIDC_X_FORWARDED_HEADERS" = "X-Forwarded-Host X-Forwarded-Port X-Forwarded-Proto";
    };
    volumes = [
      "${cfg.configDir}/freshrss:/config"
    ];
    environmentFiles = [ config.sops.secrets.freshrss.path ];
    healthCmd = "curl -f http://localhost:80/api/greader.php";
    labels = {
      "traefik.http.routers.freshrss.rule" = "Host(`rss.${cfg.domain}`)";
    };
  };
  "mercury" = {
    image = "docker.io/wangqiru/mercury-parser-api:latest";
    labels = {
      "glance.parent" = "freshrss";
      "traefik.enable" = "false";
    };
  };
}
