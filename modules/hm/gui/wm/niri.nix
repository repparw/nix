{ lib, osConfig, ... }:
let
  prefix = "uwsm app --";
  browser = "${prefix} firefox";
  # host-specific monitor setup
  monitorConfig =
    if osConfig.networking.hostName == "alpha" then
      ''
        output "DP-1" {
            mode "2560x1440@165"
            variable-refresh-rate
        }
        output "HDMI-A-1" {
            position x=-1920 y=0
        }
      ''
    else
      ''
        output "eDP-1" {
            mode "preferred"
        }
      '';
in
{
  config = lib.mkIf osConfig.programs.niri.enable {
    xdg.configFile."niri/config.kdl".text = ''
      ${monitorConfig}

      input {
          keyboard {
              xkb {
                  layout "us"
                  variant "altgr-intl"
              }
              repeat-delay 300
              repeat-rate 50
          }
          touchpad {
              natural-scroll false
          }
          mouse {
              accel-speed 0.0
              accel-profile "flat"
          }
      }

      layout {
          gaps 1
          center-focused-column "never"
          default-column-width { proportion 0.5; }

          border {
              width 1
              radius 14
          }
      }

      window-rule {
          match class="firefox"
          opacity 1.0
      }

      window-rule {
          match title="^(Picture-in-Picture|Picture in picture)$"
          open-floating true
          default-column-width { fixed 400; }
          default-window-height { fixed 225; }
      }

      binds {
          // basic ops
          Mod+Return { spawn "${prefix}" "foot"; }
          Mod+W { close-window; }
          Mod+Space { spawn "rofi" "-show" "combi"; }
          Mod+Shift+Space { spawn "${browser}"; }

          // navigation
          Mod+H { focus-column-left; }
          Mod+J { focus-window-down; }
          Mod+K { focus-window-up; }
          Mod+L { focus-column-right; }

          Mod+Shift+H { move-column-left; }
          Mod+Shift+L { move-column-right; }

          // resizing
          Mod+Ctrl+H { set-column-width "-10%"; }
          Mod+Ctrl+L { set-column-width "+10%"; }

          // workspaces
          Mod+1 { focus-workspace 1; }
          Mod+2 { focus-workspace 2; }
          Mod+3 { focus-workspace 3; }
          Mod+4 { focus-workspace 4; }
          Mod+5 { focus-workspace 5; }
          Mod+6 { focus-workspace 6; }
          Mod+7 { focus-workspace 7; }
          Mod+8 { focus-workspace 8; }
          Mod+9 { focus-workspace 9; }

          Mod+Shift+1 { move-column-to-workspace 1; }
          Mod+Shift+2 { move-column-to-workspace 2; }

          // utilities
          Mod+Alt+L { spawn "loginctl" "lock-session"; }
          XF86MonBrightnessDown { spawn "brightnessctl" "s" "5%-"; }
          XF86MonBrightnessUp { spawn "brightnessctl" "s" "5%+"; }

          // media
          XF86AudioPlay { spawn "playerctl" "play-pause"; }
          XF86AudioNext { spawn "playerctl" "next"; }
          XF86AudioPrev { spawn "playerctl" "previous"; }

          MouseForward { toggle-window-overview; }
      }
    '';
  };
}
