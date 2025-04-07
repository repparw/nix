{cfg}: {
  "ntfy" = {
    image = "binwiederhier/ntfy";
    cmd = ["serve"];
    environment = {
      "TZ" = cfg.timezone;
    };
    user = "${cfg.user}:${cfg.group}";
    volumes = [
      "${cfg.dataDir}/ntfy:/etc/ntfy:rw,Z"
    ];
  };
}
