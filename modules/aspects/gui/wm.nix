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
          whatsapp-electron

          opencode-desktop
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

          rofi =
            let
              inherit (config.lib.formats.rasi) mkLiteral;
            in
            {
              enable = true;
              modes = [
                "drun"
                "run"
                "window"
                "combi"
              ];
              extraConfig = {
                combi-modes = "drun,window";
                show-icons = true;
                hover-select = true;
                bw = 0;
                display-combi = "";
                display-drun = "";
                display-window = "";
                drun-display-format = "{name}";
                me-select-entry = "";
                me-accept-entry = "MousePrimary";
                kb-cancel = "Escape,MouseMiddle";
              };
              theme = {
                "*" = {
                  margin = mkLiteral "0px";
                  padding = mkLiteral "0px";
                  spacing = mkLiteral "0px";
                };

                "window" = {
                  location = mkLiteral "north";
                  y-offset = mkLiteral "calc(50% - 176px)";
                  width = mkLiteral "480px";
                  border-radius = mkLiteral "24px";
                };

                "mainbox" = {
                  padding = mkLiteral "12px";
                };

                "inputbar" = {
                  border = mkLiteral "2px";
                  border-radius = mkLiteral "16px";
                  padding = mkLiteral "8px 16px";
                  spacing = mkLiteral "8px";
                  children = map mkLiteral [
                    "prompt"
                    "entry"
                  ];
                };

                "entry" = {
                  placeholder = "Search";
                };

                "message" = {
                  margin = mkLiteral "12px 0 0";
                  border-radius = mkLiteral "16px";
                };

                "textbox" = {
                  padding = mkLiteral "8px 24px";
                };

                "listview" = {
                  margin = mkLiteral "12px 0 0";
                  lines = mkLiteral "8";
                  columns = mkLiteral "1";
                  fixed-height = mkLiteral "false";
                };

                "element" = {
                  border-radius = mkLiteral "16px";
                };

                "element-icon" = {
                  size = mkLiteral "1em";
                  vertical-align = mkLiteral "0.5";
                };
              };
            };
        };
      };
  };
}
