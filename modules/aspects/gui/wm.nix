{
  den,
  lib,
  ...
}:
{
  den.aspects.wm = {
    includes = [ ];

    homeManager =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          wl-clipboard
          hdrop
          hyprshot
          hyprpicker
          nautilus
          baobab
          whatsapp-electron
        ];

        services = {
          clipse = {
            enable = true;
            imageDisplay.type = "sixel";
          };

          swayidle = {
            enable = true;
            timeouts = [
              {
                timeout = 600;
                command = "niri msg action power-off-monitors";
                resumeCommand = "niri msg action power-on-monitors";
              }
              {
                timeout = 610;
                command = "loginctl lock-session";
              }
            ];
            events.before-sleep = "pidof swaylock || swaylock";
          };

          hyprpolkitagent.enable = true;

          wlsunset = {
            enable = true;
            temperature.night = 2500;
            latitude = -35.1;
            longitude = -59.8;
          };

          swaync.enable = true;
        };

        programs = {
          swaylock.enable = true;

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
                  "CustomNotifications"
                ];
              };
              CustomModule = [
                {
                  name = "CustomNotifications";
                  icon = "";
                  command = "swaync-client -t -sw";
                  listen_cmd = "swaync-client -swb";
                  alert = ".*notification";
                }
              ];
            };
          };

          rofi = {
            enable = true;
            modes = [
              "drun"
              "run"
              "window"
              "combi"
            ];
          };
        };

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
  };
}
