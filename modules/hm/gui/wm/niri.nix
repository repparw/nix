{
  lib,
  osConfig,
  config,
  pkgs,
  ...
}:
let
  isAlpha = osConfig.networking.hostName == "alpha";
  shell = "fish";
  terminal = "foot";
in
{
  config = lib.mkIf osConfig.programs.niri.enable {
    programs.niri = {
      enable = true;
      settings = {
        screenshot-path = "${config.xdg.userDirs.pictures}/ss/screenshot-%Y-%m-%d_%H-%M-%S.png";

        workspaces = {
          "1" = { };
          "2" = { };
          "3" = { };
          "4" = { };
          "5" = { };
          "6" = { };
          "7" = { };
          "8" = { };
          "9" = { };
        };

        prefer-no-csd = true;

        input = {
          keyboard = {
            xkb = {
              layout = "us";
              variant = "altgr-intl";
            };
            repeat-delay = 300;
            repeat-rate = 50;
          };
          mouse = {
            accel-speed = 0.0;
            accel-profile = "flat";
          };
        };

        layout = {
          gaps = 1;
          center-focused-column = "never";
          default-column-width = {
            proportion = 0.5;
          };
          border = {
            width = 1;
          };
        };

        window-rules = [
          {
            matches = [ { app-id = "firefox"; } ];
            opacity = 1.0;
          }
          {
            matches = [
              { title = "^(Picture-in-Picture|Picture in picture)$"; }
              { title = "(video1 - mpv)"; }
            ];
            open-floating = true;
            default-floating-position = {
              x = 10;
              y = 10;
              relative-to = "bottom-right";
            };
            default-column-width = {
              fixed = 400;
            };
            default-window-height = {
              fixed = 225;
            };
          }
          {
            matches = [ { app-id = "clipse"; } ];
            open-floating = true;
            default-column-width = {
              fixed = 622;
            };
            default-window-height = {
              fixed = 652;
            };
          }
          {
            matches = [
              { app-id = "^(.gamescope-wrapped)$"; }
              { app-id = "^(steam_app_.*)$"; }
            ];
            open-fullscreen = true;
          }
        ];

        binds = with config.lib.niri.actions; {
          # basic ops
          "Mod+Return" = {
            action = spawn "${terminal}";
            hotkey-overlay.title = "Terminal";
          };
          "Mod+W" = {
            action = close-window;
            hotkey-overlay.title = "Close Window";
          };
          "Mod+Space" = {
            action = spawn "rofi" "-show" "combi";
            hotkey-overlay.title = "App Launcher";
          };
          "Mod+Shift+Space" = {
            action = spawn "firefox";
            hotkey-overlay.title = "Browser";
          };

          # apps from hyprland
          "Mod+A" = {
            action = spawn "anki";
            hotkey-overlay.title = "Anki";
          };
          "Mod+B" = {
            action = spawn "bttoggle";
            hotkey-overlay.title = "Bluetooth Toggle";
          };
          "Mod+C" = {
            action = spawn "webapp" "https://web.whatsapp.com";
            hotkey-overlay.title = "WhatsApp";
          };
          "Mod+E" = {
            action = spawn "${terminal}" "--app-id" "filemanager" "${shell}" "-ic" "yazi";
            hotkey-overlay.title = "File Manager (Terminal)";
          };
          "Mod+Shift+E" = {
            action = spawn "nautilus";
            hotkey-overlay.title = "File Manager (GUI)";
          };
          "Mod+F" = {
            action = maximize-column;
            hotkey-overlay.title = "Fullscreen";
          };
          "Mod+Alt+F" = {
            action = toggle-window-floating;
            hotkey-overlay.title = "Toggle Floating";
          };
          "Mod+G" = {
            action = spawn "${terminal}" "--app-id" "opencode" "opencode";
            hotkey-overlay.title = "AI Agent";
          };
          "Mod+M" = {
            action = spawn "${terminal}" "--app-id" "spotify" "spotify_player";
            hotkey-overlay.title = "Spotify";
          };
          "Mod+N" = {
            action = spawn "${terminal}" "--app-id" "obsinvim" "${shell}" "-ic" "obsinvim";
            hotkey-overlay.title = "Notes (Terminal)";
          };
          "Mod+Shift+N" = {
            action = spawn "ndrop" "-c" "obsidian" "obsidian";
            hotkey-overlay.title = "Notes (Obsidian)";
          };
          "Mod+P" = {
            action = spawn "webapp" "https://noisekun.com/?theme=dark";
            hotkey-overlay.title = "Pomodoro";
          };
          "Mod+S" = {
            action = spawn "sh" "-c" "SDL_RENDER_DRIVER=opengl scrcpy --tcpip=192.168.0.32 -S";
            hotkey-overlay.title = "Scrcpy";
          };
          "Mod+T" = {
            action = spawn "${terminal}" "${shell}" "-ic" "top";
            hotkey-overlay.title = "Top";
          };
          "Mod+V" = {
            action = spawn "${terminal}" "--app-id" "clipse" "clipse";
            hotkey-overlay.title = "Clipboard";
          };
          "Mod+X" = {
            action = spawn "cfait";
            hotkey-overlay.title = "cfait";
          };
          "Mod+Y" = {
            action = spawn "firefox" "-P" "kiosk";
            hotkey-overlay.title = "Kiosk Browser";
          };
          "Mod+Z" = {
            action = spawn "mpvclip";
            hotkey-overlay.title = "MPV Clipboard";
          };

          # macropad
          "Ctrl+Alt+Shift+A" = {
            action = spawn "steam" "-bigpicture";
          };
          "Ctrl+Alt+Shift+B" = {
            action = spawn "obs-cmd" "recording" "toggle-pause";
          };
          "Ctrl+Alt+Shift+C" = {
            action = spawn "obs-remux2wsp";
          };
          "Ctrl+Alt+Shift+D" = {
            action = spawn "obs-cmd" "replay" "save";
          };
          "Ctrl+Alt+Shift+E" = {
            action = spawn "ndrop" "discord";
          };
          "Ctrl+Alt+Shift+F" = {
            action = spawn "wpctl" "set-source-mute" "@DEFAULT_SOURCE@" "toggle";
          };

          # navigation
          "Mod+H" = {
            action = focus-column-or-monitor-left;
            hotkey-overlay.title = "Focus Left";
          };
          "Mod+J" = {
            action = focus-window-or-workspace-down;
            hotkey-overlay.title = "Focus Down";
          };
          "Mod+K" = {
            action = focus-window-or-workspace-up;
            hotkey-overlay.title = "Focus Up";
          };
          "Mod+L" = {
            action = focus-column-or-monitor-right;
            hotkey-overlay.title = "Focus Right";
          };

          # workspace tab switching
          "Mod+Tab" = {
            action = spawn "niri-swap-workspaces";
            hotkey-overlay.title = "Swap Workspace";
          };

          "Mod+Shift+H" = {
            action = move-column-left-or-to-monitor-left;
          };
          "Mod+Shift+J" = {
            action = move-window-down-or-to-workspace-down;
          };
          "Mod+Shift+K" = {
            action = move-window-up-or-to-workspace-up;
          };
          "Mod+Shift+L" = {
            action = move-column-right-or-to-monitor-right;
          };

          "Mod+Ctrl+H" = {
            action = consume-or-expel-window-left;
          };
          "Mod+Ctrl+L" = {
            action = consume-or-expel-window-right;
          };

          # workspaces
          "Mod+1" = {
            action = focus-workspace "1";
          };
          "Mod+2" = {
            action = focus-workspace "2";
          };
          "Mod+3" = {
            action = focus-workspace "3";
          };
          "Mod+4" = {
            action = focus-workspace "4";
          };
          "Mod+5" = {
            action = focus-workspace "5";
          };
          "Mod+6" = {
            action = focus-workspace "6";
          };
          "Mod+7" = {
            action = focus-workspace "7";
          };
          "Mod+8" = {
            action = focus-workspace "8";
          };
          "Mod+9" = {
            action = focus-workspace "9";
          };

          "Mod+Shift+1" = {
            action = spawn "niri" "msg" "action" "move-column-to-workspace" "\"1\"";
          };
          "Mod+Shift+2" = {
            action = spawn "niri" "msg" "action" "move-column-to-workspace" "\"2\"";
          };
          "Mod+Shift+3" = {
            action = spawn "niri" "msg" "action" "move-column-to-workspace" "\"3\"";
          };
          "Mod+Shift+4" = {
            action = spawn "niri" "msg" "action" "move-column-to-workspace" "\"4\"";
          };
          "Mod+Shift+5" = {
            action = spawn "niri" "msg" "action" "move-column-to-workspace" "\"5\"";
          };
          "Mod+Shift+6" = {
            action = spawn "niri" "msg" "action" "move-column-to-workspace" "\"6\"";
          };
          "Mod+Shift+7" = {
            action = spawn "niri" "msg" "action" "move-column-to-workspace" "\"7\"";
          };
          "Mod+Shift+8" = {
            action = spawn "niri" "msg" "action" "move-column-to-workspace" "\"8\"";
          };
          "Mod+Shift+9" = {
            action = spawn "niri" "msg" "action" "move-column-to-workspace" "\"9\"";
          };

          # utilities
          "Mod+Alt+L" = {
            allow-when-locked = true;
            action = spawn "loginctl" "lock-session";
            hotkey-overlay.title = "Lock Screen";
          };

          "Mod+U" = {
            action = spawn "${terminal}" "--hold" "${shell}" "-ic" "nrsu";
            hotkey-overlay.title = "Update System";
          };
          "Mod+R" = {
            action = spawn "${terminal}" "${shell}" "-ic" "rpi";
            hotkey-overlay.title = "Rebuild Config";
          };
          "Mod+Comma" = {
            action = spawn "ndrop" "-c" "imv" "imv" "/home/repparw/code/totem/layout/totem.svg";
            hotkey-overlay.title = "Show Layout";
          };
          "Mod+Period" = {
            action = spawn "sh" "-c" "pkill wshowkeys || wshowkeys -a bottom -m 108 -b 00000066";
            hotkey-overlay.title = "Show Keys";
          };

          "Print" = {
            action = spawn "niri" "msg" "action" "screenshot-screen";
            hotkey-overlay.title = "Screenshot Screen";
          };
          "Mod+Print" = {
            action = spawn "niri" "msg" "action" "screenshot-window";
            hotkey-overlay.title = "Screenshot Window";
          };
          "Mod+Shift+Print" = {
            action = spawn "niri" "msg" "action" "screenshot";
            hotkey-overlay.title = "Screenshot Area";
          };

          # media
          "XF86AudioPlay" = {
            allow-when-locked = true;
            action = spawn "media-play-pause";
            hotkey-overlay.title = "Play/Pause";
          };
          "XF86AudioNext" = {
            allow-when-locked = true;
            action = spawn "playerctl" "--player=spotifyd" "next";
            hotkey-overlay.title = "Next Track";
          };
          "XF86AudioPrev" = {
            allow-when-locked = true;
            action = spawn "playerctl" "--player=spotifyd" "previous";
            hotkey-overlay.title = "Previous Track";
          };

          # overview
          "MouseForward" = {
            action = toggle-overview;
            hotkey-overlay.title = "Toggle Overview";
          };
          "Mod+Shift+Slash" = {
            action = show-hotkey-overlay;
            hotkey-overlay.title = "Show Hotkeys";
          };
        };
      };
    };
  };
}
