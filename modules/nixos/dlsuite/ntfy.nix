{cfg}: {
  "ntfy" = {
    image = "binwiederhier/ntfy";
    cmd = ["serve"];
    environment = {
      "TZ" = cfg.timezone;
      "NTFY_BASE_URL" = "https://ntfy.${cfg.domain}";
      "NTFY_CACHE_FILE" = "${cfg.dataDir}/ntfy/cache.db";
      "NTFY_AUTH_FILE" = "${cfg.dataDir}/ntfy/auth.db";
      "NTFY_AUTH_DEFAULT_ACCESS" = "deny-all";
      "NTFY_BEHIND_PROXY" = true;
      "NTFY_ATTACHMENT_CACHE_DIR" = "${cfg.dataDir}/ntfy/attachments";
      "NTFY_ENABLE_LOGIN" = true;
    };
    user = "${cfg.user}:${cfg.group}";
  };
}
