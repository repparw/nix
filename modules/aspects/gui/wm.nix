{
  den,
  lib,
  ...
}:
{
  den.aspects.gui.provides.wm = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          wl-clipboard
          nautilus
          baobab
          playerctl

          papers
          glycin-thumbnailer
          gst-thumbnailers
          ffmpegthumbnailer
          sushi
          libgsf
          webp-pixbuf-loader
        ];

        services = {
          swayidle = {
            enable = true;
            timeouts = [
              {
                timeout = 900;
                command = "${lib.getExe pkgs.niri} msg action power-off-monitors";
              }
              {
                timeout = 915;
                command = "${lib.getExe' pkgs.systemd "loginctl"} lock-session";
              }
            ];
            events = {
              before-sleep = "${lib.getExe' pkgs.systemd "loginctl"} lock-session";
              lock = "${lib.getExe pkgs.swaylock} -f";
              unlock = "${lib.getExe' pkgs.procps "pkill"} -USR1 swaylock";
            };
          };

          hyprpolkitagent.enable = true;

          wlsunset = {
            enable = true;
            temperature.night = 2500;
            latitude = -35.1;
            longitude = -59.8;
          };

          swaync = {
            enable = true;
            settings = {
              timeout-critical = 300;
              notification-window-preferred-output = "HDMI-A-1";
            };
          };
          playerctld.enable = true;
        };

        programs = {
          swaylock.enable = true;

          vicinae = {
            enable = true;
            systemd.enable = true;
          };

          ashell = {
            enable = true;
            systemd.enable = true;
            settings = {
              outputs = {
                Targets = [ "HDMI-A-1" ];
              };
              modules = {
                left = [ "Tempo" ];
                center = [ "MediaPlayer" ];
                right = [
                  "Tray"
                  "Settings"
                  "CustomNotifications"
                ];
              };
              tempo = {
                clock_format = "%a %d %b %R";
                weather_indicator = "None";
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
              settings = {
                CustomButton = [
                  {
                    name = "Night Light";
                    icon = "";
                    command = "systemctl --user toggle wlsunset";
                    status_command = "systemctl --user is-active wlsunset";
                    tooltip = "Toggle wlsunset night light";
                  }
                ];
              };
              appearance = {
                style = "Islands";
                opacity = 1.0;
                menu = {
                  opacity = lib.mkForce 0.95;
                  backdrop = 0.3;
                };
              };
            };
          };
        };

        systemd.user.services.vicinae.Service.Environment = [
          "VICINAE_NODE_BIN=${pkgs.nodejs-runtime}/bin/node"
        ];

        xdg.configFile."vicinae/settings.json".enable = lib.mkForce false;
      };
  };
}
