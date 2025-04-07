{cfg}: {
  "ntfy" = {
    image = "binwiederhier/ntfy";
    command = "serve";
    environment = {
      "TZ" = cfg.timezone;
    };
    user = "${cfg.user}:${cfg.group}";
  };
}
