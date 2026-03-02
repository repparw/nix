{
  programs.quickshell = {
    enable = true;
    systemd.enable = true;
    configs.bar = ./shell.qml;
    activeConfig = "bar";
  };
}
