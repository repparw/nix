{
  pkgs,
  osConfig,
  lib,
  ...
}:
{
  config = lib.mkIf (osConfig.programs.niri.enable || osConfig.programs.hyprland.enable) {
    home.packages = with pkgs; [
      wl-clipboard

      hdrop

      hyprshot
      hyprpicker

      nautilus
    ];

    services = {
      clipse = {
        enable = true;
        imageDisplay.type = "sixel";
      };

      hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "pidof hyprlock || hyprlock";
            before_sleep_cmd = "loginctl lock-session";
            after_sleep_cmd = "hyprctl dispatch dpms on";
          };

          listener = [
            {
              timeout = 600;
              on-timeout = "hyprctl dispatch dpms off";
              on-resume = "hyprctl dispatch dpms on";
            }
            {
              timeout = 610;
              on-timeout = "loginctl lock-session";
            }
          ];
        };
      };

      hyprpolkitagent.enable = true;

      wlsunset = {
        enable = true;
        temperature.night = 2500;
        latitude = -34.9;
        longitude = -57.9;
      };

      hyprpaper = {
        settings = {
          splash = false;
        };
      };
    };

    programs = {
      hyprlock.enable = true;
    };
  };
}
