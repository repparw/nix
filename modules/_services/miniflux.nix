{
  cfg,
  config,
  lib,
  ...
}:
{
  services.miniflux = {
    enable = true;
    config = {
      BASE_URL = "https://rss.${cfg.domain}";
      LISTEN_ADDR = "0.0.0.0:8081";
      CREATE_ADMIN = 0;
      RUN_MIGRATIONS = 1;
      CLEANUP_FREQUENCY_HOURS = 24;
    };
  };
}
