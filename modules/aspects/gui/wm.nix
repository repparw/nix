{
  den,
  lib,
  ...
}:
{
  den.aspects.gui.provides.wm = {
    homeManager =
      { config, pkgs, ... }:
      {
        home.packages = with pkgs; [
          wl-clipboard
          nautilus
          baobab
          playerctl

          opencode-desktop
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

          swaync.enable = true;
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
      };
  };
}
