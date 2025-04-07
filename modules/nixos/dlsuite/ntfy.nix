{cfg}: {
  "ntfy" = {
    image = "binwiederhier/ntfy";
    command = "serve";
    env = {
      "TZ" = cfg.timezone;
    };
    user = "${cfg.user}:${cfg.group}";
  };
}
