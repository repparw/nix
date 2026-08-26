{
  den,
  lib,
  pkgs,
  ...
}:
{
  den.aspects.gui.provides.niri = {
    nixos =
      { pkgs, ... }:
      {
        nixpkgs.overlays = [
          (final: prev: {
            ndrop = final.callPackage ../_packages/ndrop.nix { };
            wshowkeys = prev.wshowkeys.overrideAttrs (old: {
              src = prev.fetchFromGitHub {
                owner = "repparw";
                repo = "wshowkeys";
                rev = "52d1191cc250d3a24b83f77ce23f23d498c23bb3";
                hash = "sha256-BkmB+/oG0tsAbvAjkoEAJxObjvg+mCENhM4EHDDXQAI=";
              };
            });
          })
        ];

        programs.niri.enable = lib.mkDefault true;
        programs.wshowkeys.enable = true;

        environment.systemPackages = [ pkgs.xwayland-satellite ];
      };

    homeManager =
      { pkgs, ... }:
      let
        titledAction = title: action: {
          _props.hotkey-overlay-title = title;
          ${action} = { };
        };
        titledSpawn = title: command: {
          _props.hotkey-overlay-title = title;
          spawn = command;
        };
        spawn = command: { spawn = command; };
      in
      {
        home.packages = with pkgs; [
          ndrop

          (writeShellApplication {
            name = "record";
            runtimeInputs = [
              wl-screenrec
              slurp
              niri
              jq
              libnotify
              wl-clipboard
            ];
            text = builtins.readFile ./niri-record.sh;
          })

          (writeShellApplication {
            name = "grabtext";
            runtimeInputs = [
              grim
              gnugrep
              slurp
              tesseract
              wl-clipboard
            ];
            text = ''
              if wl-paste --list-types | grep -q '^image/'; then
                wl-paste --type image/png | tesseract stdin stdout -l "''${TESSERACT_LANGS:-eng}" | wl-copy
              else
                geom=$(slurp -b "#ff000040" -c "#ff0000ff" -w 2) || exit 0
                grim -g "$geom" -t png - | tesseract stdin stdout -l "''${TESSERACT_LANGS:-eng}" | wl-copy
              fi
            '';
          })

          (writeShellApplication {
            name = "niri-swap-active-monitor-windows";
            runtimeInputs = [
              niri
              jq
            ];
            text = builtins.readFile ./niri-swap-active-monitor-windows.sh;
          })
        ];

        wayland.windowManager.niri = {
          enable = true;
          package = pkgs.niri;
          systemd.enable = false;
          portalPackage = null;
          xwaylandSatellitePackage = null;

          settings = {
            screenshot-path = "/home/repparw/Pictures/ss/screenshot-%Y-%m-%d_%H-%M-%S.png";
            prefer-no-csd = { };

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
              focus-follows-mouse._props.max-scroll-amount = "10%";
            };

            gestures.hot-corners.off = { };

            layout = {
              always-center-single-column = { };
              center-focused-column = "never";
              empty-workspace-above-first = { };
              default-column-display = "tabbed";
              tab-indicator.hide-when-single-tab = { };
              default-column-width.proportion = 0.5;
              gaps = 1;
              border.off = { };
              focus-ring.width = 1;
            };

            cursor = {
              xcursor-theme = "BreezeX-RosePine-Linux";
              xcursor-size = 24;
            };
            overview.backdrop-color = "#141414";
            hotkey-overlay = {
              skip-at-startup = { };
              hide-not-bound = { };
            };
            debug.honor-xdg-activation-with-invalid-serial = { };

            spawn-sh-at-startup = "systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP NIRI_SOCKET";

            binds = {
              "Mod+Return" = titledSpawn "Terminal" [ "foot" ];
              "Mod+W" = titledAction "Close Window" "close-window";
              "Mod+Space" = titledSpawn "App Launcher" [
                "vicinae"
                "toggle"
              ];
              "Mod+Shift+Space" = titledSpawn "Browser" [ "firefox" ];

              "Mod+A" = titledSpawn "Anki" [ "anki" ];
              "Mod+B" = titledSpawn "Bluetooth Toggle" [ "bttoggle" ];
              "Mod+C" = titledSpawn "WhatsApp" [
                "ndrop"
                "-F"
                "-c"
                "zapzap"
                "zapzap"
              ];
              "Mod+D" = {
                _props = {
                  repeat = false;
                  hotkey-overlay-title = "Dictate";
                };
                spawn = [ "voxtype-toggle" ];
              };
              "Mod+Shift+D" = {
                _props = {
                  repeat = false;
                  hotkey-overlay-title = "Translate Selection";
                };
                spawn = [ "translate-selection" ];
              };
              "Mod+Shift+V" = titledSpawn "Send Clipboard or Files to Phone" [
                "kdeconnect-send-clipboard"
              ];
              "Mod+E" = titledSpawn "File Manager (Terminal)" [
                "foot"
                "--app-id"
                "filemanager"
                "fish"
                "-ic"
                "yazi"
              ];
              "Mod+Shift+E" = titledSpawn "File Manager (GUI)" [ "nautilus" ];
              "Mod+F" = titledAction "Fullscreen" "maximize-window-to-edges";
              "Mod+Alt+F" = titledAction "Toggle Floating" "toggle-window-floating";
              "Mod+Ctrl+F" = titledAction "Toggle Focus Floating" "switch-focus-between-floating-and-tiling";
              "Mod+G" = titledSpawn "T3 Code" [ "t3code-desktop" ];
              "Mod+M" = titledSpawn "Spotify" [
                "foot"
                "--app-id"
                "spotify"
                "spotify_player"
              ];
              "Mod+N" = titledSpawn "Notes (Neovim)" [
                "foot"
                "--app-id"
                "notes"
                "sh"
                "-c"
                "cd \"$HOME/Documents/obsidian\" && note=\"$(find . -type f -name '*.md' -not -path './.git/*' -not -path './.obsidian/*' -not -path './.trash/*' -printf '%T@ %p\\n' | sort -nr | head -n1 | cut -d' ' -f2-)\" && exec nvim -- \"$note\""
              ];
              "Mod+P" = titledSpawn "Pomodoro" [
                "webapp"
                "https://app.solidtime.io"
              ];
              "Mod+S" = titledSpawn "Scrcpy" [
                "sh"
                "-c"
                "SDL_RENDER_DRIVER=opengl scrcpy --tcpip=192.168.0.32 -S"
              ];
              "Mod+T" = titledSpawn "Top" [
                "foot"
                "fish"
                "-ic"
                "top"
              ];
              "Mod+Alt+T" = titledSpawn "Grab Text" [ "grabtext" ];
              "Mod+V" = titledSpawn "Clipboard" [
                "vicinae"
                "vicinae://launch/clipboard/history"
              ];
              "Mod+X" = titledSpawn "Tasks" [ "tasks-org" ];
              "Mod+Y" = titledSpawn "YouTube" [
                "ndrop"
                "-F"
                "-c"
                "chrome-agimnkijcaahngcdmfeangaknmldooml-Default"
                "chromium"
                "--password-store=basic"
                "--profile-directory=Default"
                "--app-id=agimnkijcaahngcdmfeangaknmldooml"
              ];
              "Mod+Z" = titledSpawn "MPV Clipboard" [ "mpvclip" ];

              "Ctrl+Alt+Shift+A".spawn-sh =
                "gamescope --steam -H 1080 --adaptive-sync --fps-limit 162 -- steam -tenfoot -pipewire-dmabuf";
              "Ctrl+Alt+Shift+E" = spawn [ "Discord" ];
              "Ctrl+Alt+Shift+F" = spawn [
                "wpctl"
                "set-source-mute"
                "@DEFAULT_SOURCE@"
                "toggle"
              ];

              "Mod+H" = titledAction "Focus Left" "focus-column-or-monitor-left";
              "Mod+J" = titledAction "Focus Down" "focus-window-or-workspace-down";
              "Mod+K" = titledAction "Focus Up" "focus-window-or-workspace-up";
              "Mod+L" = titledAction "Focus Right" "focus-column-or-monitor-right";
              "Mod+Tab" = titledAction "Focus Next Monitor" "focus-monitor-next";
              "Mod+Shift+Tab" = titledAction "Move Window to Next Monitor" "move-window-to-monitor-next";
              "Mod+Alt+Tab" = titledSpawn "Swap Active Monitor Windows" [ "niri-swap-active-monitor-windows" ];

              "Mod+Shift+H".move-column-left-or-to-monitor-left = { };
              "Mod+Shift+J".move-window-down-or-to-workspace-down = { };
              "Mod+Shift+K".move-window-up-or-to-workspace-up = { };
              "Mod+Shift+L".move-column-right-or-to-monitor-right = { };
              "Mod+Ctrl+H".consume-or-expel-window-left = { };
              "Mod+Ctrl+L".consume-or-expel-window-right = { };

              "Mod+Alt+L" = {
                _props = {
                  allow-when-locked = true;
                  hotkey-overlay-title = "Lock screen and turn off monitors";
                };
                spawn-sh = "loginctl lock-session && sleep 3 && niri msg action power-off-monitors";
              };
              "Mod+U" = titledSpawn "Update System" [
                "foot"
                "--hold"
                "fish"
                "-ic"
                "nrsu"
              ];
              "Mod+R" = titledSpawn "Raspberry Pi" [
                "foot"
                "fish"
                "-ic"
                "rpi"
              ];
              "Mod+Comma" = titledSpawn "Show Layout" [
                "ndrop"
                "-c"
                "imv"
                "imv"
                "/home/repparw/Projects/totem/layout/totem.svg"
              ];
              "Mod+Period" = titledSpawn "Show Keys" [
                "sh"
                "-c"
                "pkill wshowkeys || wshowkeys -a bottom -m 108 -b 000000BB"
              ];

              Print = titledSpawn "Screenshot Screen" [
                "niri"
                "msg"
                "action"
                "screenshot-screen"
              ];
              "Mod+Print" = titledSpawn "Screenshot Window" [
                "niri"
                "msg"
                "action"
                "screenshot-window"
              ];
              "Mod+Shift+Print" = titledSpawn "Screenshot Area" [
                "niri"
                "msg"
                "action"
                "screenshot"
                "-p"
                "false"
              ];
              "Ctrl+Print" = titledSpawn "Record Screen" [
                "record"
                "screen"
              ];
              "Ctrl+Mod+Shift+Print" = titledSpawn "Record Area" [
                "record"
                "area"
              ];

              XF86AudioPlay = {
                _props = {
                  allow-when-locked = true;
                  hotkey-overlay-title = "Play/Pause";
                };
                spawn = [
                  "playerctl"
                  "play-pause"
                ];
              };
              XF86AudioPause = {
                _props = {
                  allow-when-locked = true;
                  hotkey-overlay-title = "Play/Pause";
                };
                spawn = [
                  "playerctl"
                  "play-pause"
                ];
              };
              XF86AudioNext = {
                _props = {
                  allow-when-locked = true;
                  hotkey-overlay-title = "Next Track";
                };
                spawn = [
                  "playerctl"
                  "next"
                ];
              };
              XF86AudioPrev = {
                _props = {
                  allow-when-locked = true;
                  hotkey-overlay-title = "Previous Track";
                };
                spawn = [
                  "playerctl"
                  "previous"
                ];
              };
              MouseForward = titledAction "Toggle Overview" "toggle-overview";
              "Mod+Shift+Slash" = titledAction "Show Hotkeys" "show-hotkey-overlay";
            };

            _children = [
              {
                output = {
                  _args = [ "DP-1" ];
                  mode = "1920x1080";
                  position._props = {
                    x = 0;
                    y = 0;
                  };
                  variable-refresh-rate._props.on-demand = true;
                };
              }
              {
                output = {
                  _args = [ "HDMI-A-1" ];
                  position._props = {
                    x = -1920;
                    y = 0;
                  };
                };
              }
              {
                window-rule = {
                  match._props.app-id = "firefox";
                  opacity = 1.0;
                };
              }
              {
                window-rule._children = [
                  { match._props.title = "^(Picture-in-Picture|Picture in picture)$"; }
                  { match._props.title = "(video1 - mpv)"; }
                  { open-floating = true; }
                  { open-focused = false; }
                  {
                    default-floating-position._props = {
                      x = 10;
                      y = 10;
                      relative-to = "bottom-right";
                    };
                  }
                  { default-column-width.fixed = 600; }
                  { default-window-height.fixed = 338; }
                ];
              }
              {
                window-rule._children = [
                  { match._props.app-id = "^(gamescope)$"; }
                  { match._props.app-id = "^(steam_app_.*)$"; }
                  { open-fullscreen = true; }
                  { variable-refresh-rate = true; }
                ];
              }
              {
                window-rule = {
                  match._props.app-id = "chrome-agimnkijcaahngcdmfeangaknmldooml-Default";
                  open-on-output = "HDMI-A-1";
                  default-column-width.proportion = 1.0;
                };
              }
              {
                window-rule = {
                  match._props.app-id = "MainKt";
                  open-fullscreen = true;
                };
              }
            ];
          };
        };

        services.wpaperd.enable = true;
      };
  };
}
