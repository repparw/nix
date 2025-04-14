{cfg}: {
  "ntfy" = {
    image = "docker.io/binwiederhier/ntfy:latest";
    exec = "serve";
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
    ports = [
      "90:80/tcp"
    ];
    volumes = [
      "${cfg.dataDir}/ntfy:/etc/ntfy:rw,Z"
    ];
  };
}
