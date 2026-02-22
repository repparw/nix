{
  ...
}:
{
  programs.noctalia-shell = {
    enable = true;
    systemd.enable = true;
    settings = {
      bar = {
        location.weatherEnabled = false;
        density = "compact";
        position = "top";
        monitors = [ "HDMI-A-1" ];
        widgets = {
          left = [
            { id = "Launcher"; }
            { id = "Clock"; }
          ];
          center = [
            {
              id = "MediaMini";
              compactMode = true;
              maxWidth = 500;
              showAlbumArt = false;
            }
          ];
          right = [
            {
              id = "Tray";
              drawerEnabled = false;
            }
            { id = "Battery"; }
            { id = "ControlCenter"; }
          ];
        };
      };
    };
  };
}
