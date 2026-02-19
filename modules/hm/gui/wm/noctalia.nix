{
  lib,
  inputs,
  ...
}:
{
  programs.noctalia-shell = {
    enable = true;
    systemd.enable = true;
    settings = {
      bar = {
        density = "compact";
        position = "top";
        monitors = [
          "HDMI-A-1"
        ];
        widgets = {
          left = [
            { id = "Launcher"; }
            { id = "Workspace"; }
          ];
          center = [ ];
          right = [
            { id = "Tray"; }
            { id = "Battery"; }
            { id = "Clock"; }
            { id = "ControlCenter"; }
          ];
        };
      };
      colorSchemes = {
        predefinedScheme = "Monochrome";
      };
    };
  };
}
