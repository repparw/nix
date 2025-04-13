{
  osConfig,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./hypr-pkgs.nix
    ./waybar.nix
  ];

  config = lib.mkIf osConfig.programs.hyprland.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = false;
      plugins = with pkgs.hyprlandPlugins; [
        hyprsplit
      ];

      systemd.variables = ["--all"];
      extraConfig =
        if osConfig.networking.hostName == "alpha"
        then ''
          $monitor=DP-2
          $monitor2=HDMI-A-1

          monitor=$monitor,highrr,0x0,1,vrr,2 # DP, 165hz, can enable VRR on fullscreen (,vrr,2)
          monitor=$monitor2,preferred,-1920x0,1

          workspace = 5, on-created-empty:[silent] $socials
        ''
        else ''
          monitor = eDP-1,preferred,auto,1
          monitor = ,preferred,auto,1

          # backlight TODO
          bind = ,XF86MonBrightnessDown, exec, brightnessctl s 5%-
          bind = ,XF86MonBrightnessUp, exec, brightnessctl s 5%+
        '';
      settings = {
        # GUI
        "$prefix" = "uwsm app --";

        "$browser" = "$prefix firefox";
        "$socials" = "$browser -P socials";
        "$kiosk" = "$browser -P kiosk";
        "$browser2" = "$prefix chromium-browser";
        "$discord" = "$prefix vesktop";
        "$GUIfileManager" = "$prefix nautilus";
        #"$pomodoro" = "pomatez";
        "$showkeys" = "wshowkeys -a bottom -m 108 -b 00000066";
        "$screenshot" = "hyprshot -o $XDG_SCREENSHOTS_DIR -m";
        "$desktopmenu" = "killall tofi-drun || tofi-drun";
        #"$emojimenu" = "killall tofi || BEMOJI_PICKER_CMD=${lib.getExe pkgs.tofi} bemoji -n";
        "$cmdmenu" = "killall tofi-run || tofi-run | xargs hyprctl dispatch exec --";

        "$showlayout" = "hdrop feh -g 774x275 /home/repparw/src/kbd/docs/layout.png";

        "$lockscreen" = "loginctl lock-session";

        "$screenoff" = "sleep 3 && hyprctl dispatch dpms off";

        # Terminal
        "$terminal" = "kitty";
        "$top" = "$terminal zsh -ic top";
        "$fileManager" = "hdrop $terminal --class filemanager zsh -ic yazi";
        "$spotify" = "$terminal --class spotify spotify_player";
        "$notes" = "hdrop -c obsinvim '$terminal --class obsinvim zsh -ic obsinvim'";
        "$notes2" = "hdrop -c obsidian 'obsidian'";

        # Autostart
        # Almost everything should use systemd services instead (see uwsm for autostart)
        # exec-once = [ ];

        general = {
          gaps_in = "1";
          gaps_out = "0";

          border_size = "1";

          "col.active_border" = "rgba(D4BE98FF)";
          "col.inactive_border" = "rgba(ebdbb211)";

          # Set to true enable resizing windows by clicking and dragging on borders and gaps
          resize_on_border = "false";

          allow_tearing = "false";

          layout = "dwindle";
        };

        plugin = {
          hyprsplit = {
            num_workspaces = 9;
          };
        };

        decoration = {
          rounding = "14";
          dim_inactive = "true";
          dim_strength = "0.1";
          active_opacity = "1";
          inactive_opacity = "1";
          # Your blur "amount" is blur_size * blur_passes, but high blur_size (over around 5-ish) will produce artifacts.
          # if you want heavy blur, you need to up the blur_passes.
          # the more passes, the more you can up the blur_size without noticing artifacts.
        };

        animations = {
          enabled = true;

          bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";

          animation = [
            "windows, 1, 7, myBezier"
            "windowsOut, 1, 7, default, popin 80%"
            "border, 1, 10, default"
            "borderangle, 1, 8, default"
            "fade, 1, 7, default"
            "workspaces, 1, 10, default"
          ];
        };

        dwindle = {
          pseudotile = "true"; # Master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
          preserve_split = "true"; # You probably want this
        };

        misc = {
          force_default_wallpaper = "0";
          disable_hyprland_logo = "true";

          key_press_enables_dpms = true; # mouse_move is false by default
        };

        input = {
          kb_layout = "us";
          kb_variant = "altgr-intl";
          repeat_rate = 50; # def 25
          repeat_delay = 300; # def 600
          follow_mouse = 1;
          force_no_accel = true;

          sensitivity = 0;

          touchpad = {
            natural_scroll = false;
          };
        };

        gestures = {
          workspace_swipe = false;
          workspace_swipe_forever = true;
        };

        "$mod" = "SUPER";

        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];
        binde = [
          # Resize window
          "$mod CTRL, H, resizeactive, -10 0"
          "$mod CTRL, J, resizeactive, 0 10"
          "$mod CTRL, K, resizeactive, 0 -10"
          "$mod CTRL, L, resizeactive, 10 0"
        ];
        bindl = ["$mod ALT, L, exec, $lockscreen; $screenoff"];
        bind =
          [
            "$mod, d, exec, $desktopmenu"
            "$mod SHIFT, d, exec, $cmdmenu"

            "$mod, TAB, split:swapactiveworkspaces, current +1"

            "$mod, X, focusmonitor,+1 "
            "SHIFT $mod, X, movewindow,mon:+1"

            # Scroll through monitor active workspaces with mainMod + scroll
            "$mod, C, workspace, m+1"
            ", mouse:276, workspace, m+1"
            "$mod SHIFT, C, workspace, previous_per_monitor"

            "$mod, comma, exec, [float; noinitialfocus; noborder; center] $showlayout"

            "$mod, RETURN, exec, $terminal"
            "$mod, W, killactive,"
            "$mod, M, exec, hdrop $spotify"
            "$mod, E, exec, $fileManager"
            "$mod, F, fullscreen"
            "$mod ALT, F, togglefloating"
            "$mod SHIFT, E, exec, $GUIfileManager"
            "$mod, SPACE, exec, $browser"
            "$mod SHIFT, SPACE, exec, $browser2"
            "$mod, T, exec, $top"
            "$mod, Y, exec, [monitor HDMI-A-1;noinitialfocus] $kiosk"
            "$mod, U, exec, $terminal --hold zsh -ic nup"
            "$mod, V, exec, $kiosk jellyfin.repparw.me"
            "$mod, Z, exec, $prefix mpvclip"
            "$mod, N, exec, $notes"
            "$mod SHIFT, N, exec, $notes2"
            "$mod, R, exec, $terminal zsh -ic rpi"
            "$mod, B, exec, $prefix bttoggle"
            "$mod, P, exec, $prefix scrcpy -e -S"
            #"$mod, P, exec, [monitor 1;workspace 2 silent;float;size 5% 3%;move 79% 2%] hdrop $pomodoro"

            ", Print, exec, $screenshot active -m output ## Active monitor"
            "$mod, Print, exec, $screenshot active -m window ## Active window"
            "Shift $mod, Print, exec, $screenshot region -z ## Region"

            "$mod, O, exec, wl-paste | tesseract - stdout | wl-copy ## OCR"
            "$mod, Q, exec, wl-paste --type image/png | zbarimg --raw - | wl-copy ## OCR"

            # Macropad churrosoft
            "CTRL ALT SHIFT, A, exec, hdrop steam"
            "CTRL ALT SHIFT, B, exec, obs-cmd recording toggle-pause"
            "CTRL ALT SHIFT, C, exec, obs_remux2wsp"
            "CTRL ALT SHIFT, D, exec, obs-cmd replay save"
            "CTRL ALT SHIFT, E, exec, hdrop $discord"
            "CTRL ALT SHIFT, F, exec, wpctl set-source-mute @DEFAULT_SOURCE@ toggle"
            # CTRL ALT SHIFT, G, exec,
            "CTRL ALT SHIFT, H, exec, hdrop $spotify"

            # Media keys
            ", XF86AudioPlay, exec, playerctl play-pause"
            ", XF86AudioPause, exec, playerctl play-pause"
            ", XF86AudioNext, exec, playerctl next"
            ", XF86AudioPrev, exec, playerctl previous"

            # Move focus with mainMod + arrow keys
            "$mod, H, movefocus, l"
            "$mod, J, movefocus, d"
            "$mod, K, movefocus, u"
            "$mod, L, movefocus, r"

            # Move window
            "$mod SHIFT, H, movewindow, l"
            "$mod SHIFT, J, movewindow, d"
            "$mod SHIFT, K, movewindow, u"
            "$mod SHIFT, L, movewindow, r"

            # Scroll through monitor active workspaces with mainMod + scroll
            "$mod, mouse_down, split:workspace, m+1"
            "$mod, mouse_up, split:workspace, m-1"
          ]
          ++ (
            # workspaces
            builtins.concatLists (builtins.genList (
                i: let
                  ws = i + 1;
                in [
                  "$mod, ${toString ws}, split:workspace, ${toString ws}"
                  "$mod SHIFT, ${toString ws}, split:movetoworkspace, ${toString ws}"
                ]
              )
              9)
          );

        workspace = [
          "1, monitor:0, default:true"
          "w[tv1], gapsout:0, gapsin:0"
          "f[1], gapsout:0, gapsin:0"
        ];

        windowrulev2 = [
          "monitor 1,class:^(mpv)$"
          "noinitialfocus,class:^(mpv)$"
          "noblur,class:^(mpv)$"
          "nodim,class:^(mpv)$"
          "fullscreen,class:^(mpv)$"

          "noblur,class:^(org.mozilla.firefox)$"
          "opaque,class:^(org.mozilla.firefox)$"
          "nodim,class:^(org.mozilla.firefox)$"

          "noborder, onworkspace:w[t1]"
          "bordersize 0, floating:0, onworkspace:w[tv1]"
          "rounding 0, floating:0, onworkspace:w[tv1]"
          "bordersize 0, floating:0, onworkspace:f[1]"
          "rounding 0, floating:0, onworkspace:f[1]"

          # webcam
          "float, title:(video1 - mpv)"
          "monitor 0, title:(video1 - mpv)"
          "pin, title:(video1 - mpv)"
          "size 20% 20%, title:(video1 - mpv)"
          "size 400 225, title:(video1 - mpv)"
          "move 100%-w-25 100%-w-0, title:(video1 - mpv)"

          # TODO handle all games?
          "nodim, class:^(cs2)$"
          "noblur, class:^(cs2)$"
          "maximize, class:^(cs2)$"
          "immediate, class:^(cs2)$"

          "float, title:^(Picture-in-Picture|Picture in picture)$"
          "monitor 0, title:^(Picture-in-Picture|Picture in picture)$"
          "move 100%-w-25 100%-w-3, title:^(Picture-in-Picture|Picture in picture)$"
          "size 400 225, title:^(Picture-in-Picture|Picture in picture)$"
          "pin, title:^(Picture-in-Picture|Picture in picture)$"
        ];
      };
    };
  };
}
