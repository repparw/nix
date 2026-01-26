{
  lib,
  osConfig,
  config,
  pkgs,
  ...
}:
let
  prefix = "uwsm app --";
  term = "foot";
  shell = "fish";
  browser = "${prefix} firefox";

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

      screenshot-path "${config.xdg.userDirs.pictures}/ss/screenshot-%Y-%m-%d_%H-%M-%S.png"

      prefer-no-csd

      input {
          keyboard {
              xkb {
                  layout "us"
                  variant "altgr-intl"
              }
              repeat-delay 300
              repeat-rate 50
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
          }
      }

      window-rule {
          match app-id="firefox"
          opacity 1.0
      }

      window-rule {
          match title="^(Picture-in-Picture|Picture in picture)$"
          match title="(video1 - mpv)"

          open-floating true
          default-floating-position x=10 y=10 relative-to="bottom-right"
          default-column-width { fixed 400; }
          default-window-height { fixed 225; }
          // sticky/pinned true
      }

      window-rule {
          match app-id="clipse"

          open-floating true
          default-column-width { fixed 622; }
          default-window-height { fixed 652; }
      }

      window-rule {
          // gamescope / games
          match app-id="^(.gamescope-wrapped)$"
          match app-id="^(steam_app_.*)$"

          open-fullscreen true
      }

      binds {
          // basic ops
          Mod+Return hotkey-overlay-title="Terminal" { spawn "${prefix}" "${term}"; }
          Mod+W hotkey-overlay-title="Close Window" { close-window; }
          Mod+Space hotkey-overlay-title="App Launcher" { spawn "rofi" "-show" "combi"; }
          Mod+Shift+Space hotkey-overlay-title="Browser" { spawn "${browser}"; }

          // apps from hyprland
          Mod+A hotkey-overlay-title="Anki" { spawn "${prefix} anki"; }
          Mod+B hotkey-overlay-title="Bluetooth Toggle" { spawn "${prefix} bttoggle"; }
          Mod+C hotkey-overlay-title="WhatsApp" { spawn "${prefix} webapp https://web.whatsapp.com"; }
          Mod+E hotkey-overlay-title="File Manager (Terminal)" { spawn "${prefix} ${term} --app-id filemanager ${shell} -ic yazi"; }
          Mod+Shift+E hotkey-overlay-title="File Manager (GUI)" { spawn "${prefix}" "nautilus"; }
          Mod+F hotkey-overlay-title="Fullscreen" { maximize-window-to-edges; }
          Mod+Alt+F hotkey-overlay-title="Toggle Floating" { toggle-float; }
          Mod+G hotkey-overlay-title="Gemini" { spawn "${prefix} webapp https://gemini.google.com/app"; }
          Mod+M hotkey-overlay-title="Spotify" { spawn "${prefix} ${term} --app-id spotify spotify_player"; }
          Mod+N hotkey-overlay-title="Notes (Terminal)" { spawn "${prefix} ${term} --app-id obsinvim ${shell} -ic obsinvim"; }
          Mod+Shift+N hotkey-overlay-title="Notes (Obsidian)" { spawn "ndrop" "-a obsidian ${prefix} obsidian"; }
          Mod+P hotkey-overlay-title="Pomodoro" { spawn "webapp" "https://noisekun.com/?theme=dark"; }
          Mod+S hotkey-overlay-title="Scrcpy" { spawn "${prefix} sh -c 'SDL_RENDER_DRIVER=opengl scrcpy --tcpip=192.168.0.32 -S'"; }
          Mod+T hotkey-overlay-title="Top" { spawn "${term} ${shell} -ic  top"; }
          Mod+V hotkey-overlay-title="Clipboard" { spawn "${prefix} ${term} --app-id clipse clipse"; }
          Mod+X hotkey-overlay-title="Planify" { spawn "${prefix} io.github.alainm23.planify"; }
          Mod+Y hotkey-overlay-title="Kiosk Browser" { spawn "${prefix} firefox -P kiosk"; }
          Mod+Z hotkey-overlay-title="MPV Clipboard" { spawn "${prefix}" "mpvclip"; }

          // macropad
          Ctrl+Alt+Shift+A { spawn "${prefix} steam -bigpicture"; }
          Ctrl+Alt+Shift+B { spawn "obs-cmd recording toggle-pause"; }
          Ctrl+Alt+Shift+C { spawn "obs-remux2wsp"; }
          Ctrl+Alt+Shift+D { spawn "obs-cmd replay save"; }
          Ctrl+Alt+Shift+E { spawn "ndrop" "discord"; }
          Ctrl+Alt+Shift+F { spawn "wpctl set-source-mute @DEFAULT_SOURCE@ toggle"; }

           // navigation
           Mod+H hotkey-overlay-title="Focus Left" { focus-column-left; }
           Mod+J hotkey-overlay-title="Focus Down" { focus-window-down; }
           Mod+K hotkey-overlay-title="Focus Up" { focus-window-up; }
           Mod+L hotkey-overlay-title="Focus Right" { focus-column-right; }

           // workspace tab switching
           Mod+Tab { focus-workspace-down; }
           Mod+Shift+Tab { focus-workspace-up; }

          Mod+Shift+H { move-column-left-or-to-monitor-left; }
          Mod+Shift+J { move-window-down; }
          Mod+Shift+K { move-window-up; }
          Mod+Shift+L { move-column-right-or-to-monitor-right; }

          Mod+Ctrl+H { consume-or-expel-window-left; }
          Mod+Ctrl+L { consume-or-expel-window-right; }

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
          Mod+Shift+3 { move-column-to-workspace 3; }
          Mod+Shift+4 { move-column-to-workspace 4; }
          Mod+Shift+5 { move-column-to-workspace 5; }
          Mod+Shift+6 { move-column-to-workspace 6; }
          Mod+Shift+7 { move-column-to-workspace 7; }
          Mod+Shift+8 { move-column-to-workspace 8; }
          Mod+Shift+9 { move-column-to-workspace 9; }

           // utilities
           Mod+Alt+L hotkey-overlay-title="Lock Screen" { spawn "loginctl" "lock-session"; }

           Mod+U hotkey-overlay-title="Update System" { spawn " nrsu"; }
           Mod+R hotkey-overlay-title="Rebuild Config" { spawn " rpi"; }
           Mod+Comma hotkey-overlay-title="Show Layout" { spawn "hdrop" "-c" "imv" "imv /home/repparw/src/totem/layout/totem.svg"; }
           Mod+Period hotkey-overlay-title="Show Keys" { spawn "pkill wshowkeys || ${prefix} wshowkeys -a bottom -m 108 -b 00000066"; }

          Print hotkey-overlay-title="Screenshot Screen" { screenshot-screen; }
          Mod+Print hotkey-overlay-title="Screenshot Window" { screenshot-window; }
          Mod+Shift+Print hotkey-overlay-title="Screenshot Area" { screenshot; }

          // media
          XF86AudioPlay hotkey-overlay-title="Play/Pause" { spawn "playerctl" "play-pause"; }
          XF86AudioNext hotkey-overlay-title="Next Track" { spawn "playerctl" "next"; }
          XF86AudioPrev hotkey-overlay-title="Previous Track" { spawn "playerctl" "previous"; }

          MouseForward hotkey-overlay-title="Toggle Overview" { toggle-overview; }
      }
    '';
  };
}
