{ cfg, ... }:
{
  "ntfy" = {
    image = "docker.io/binwiederhier/ntfy:latest";
    cmd = [ "serve" ];
    environment = {
      TZ = cfg.timezone;
      NTFY_BASE_URL = "https://ntfy.${cfg.domain}";
      NTFY_CACHE_FILE = "/etc/ntfy/cache.db";
      NTFY_AUTH_FILE = "/etc/ntfy/auth.db";
      NTFY_AUTH_DEFAULT_ACCESS = "deny-all";
      NTFY_BEHIND_PROXY = "true";
      NTFY_ATTACHMENT_CACHE_DIR = "/etc/ntfy/attachments";
      NTFY_ENABLE_LOGIN = "true";
    };
    volumes = [
      "${cfg.configDir}/ntfy:/etc/ntfy"
    ];
    extraOptions = [
      "--health-cmd=wget -q --tries=1 http://localhost:80/v1/health -O - | grep -Eo '\"healthy\"\\s*:\\s*true' || exit 1"
    ];
  };
}
