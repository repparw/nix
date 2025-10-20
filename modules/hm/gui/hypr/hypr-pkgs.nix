{
  pkgs,
  osConfig,
  lib,
  ...
}:
{
  config = lib.mkIf osConfig.programs.hyprland.enable {
    home.packages = with pkgs; [
      wl-clipboard

      hdrop

      hyprshot
      hyprpicker

      nautilus
    ];

    services = {
      clipse.enable = true;

      hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "hyprlock";
            before_sleep_cmd = "loginctl lock-session";
            after_sleep_cmd = "hyprctl dispatch dpms on";
            ignore_dbus_inhibit = false;
          };

          listener = [
            {
              timeout = 900;
              on-timeout = "hyprctl dispatch dpms off";
              on-resume = "hyprctl dispatch dpms on";
            }
            {
              timeout = 910;
              on-timeout = "loginctl lock-session";
            }
          ];
        };
      };

      hyprpolkitagent.enable = true;

      swww.enable = true;

      wlsunset = {
        enable = true;
        temperature.night = 2500;
        latitude = -34.9;
        longitude = -57.9;
      };
    };

    programs = {
      hyprlock.enable = true;
    };
  };
}
