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

      whatsapp-electron
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
            after_sleep_cmd = "hyprctl dispatch dpms on || niri msg action power-on-monitors";
          };

          listener = [
            {
              timeout = 600;
              on-timeout = "hyprctl dispatch dpms off || niri msg action power-off-monitors";
              on-resume = "hyprctl dispatch dpms on || niri msg action power-on-monitors";
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
        latitude = -35.1;
        longitude = -59.8;
      };

      hyprpaper = {
        settings = {
          splash = false;
        };
      };
    };

    programs = {
      hyprlock.enable = true;
      ashell = {
        enable = true;
        systemd.enable = true;
        settings = {
          outputs = {
            Targets = [ "HDMI-A-1" ];
          };
          modules = {
            left = [ "Clock" ];
            center = [ "MediaPlayer" ];
            right = [
              "Tray"
              "Settings"
            ];
          };
        };
      };
    };

    # Fix wlsunset not starting on boot/rebuild
    systemd.user.services.wlsunset = {
      Unit = {
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };
      Service = {
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
