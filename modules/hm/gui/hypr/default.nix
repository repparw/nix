{
  osConfig,
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./hypr-pkgs.nix
    ./panel.nix
    ./rofi.nix
  ];

  config = lib.mkIf osConfig.programs.hyprland.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = false; # handled by uwsm
      plugins = with pkgs.hyprlandPlugins; [
        # change requires hyprland restart
        hyprexpo
        hyprsplit
      ];

      systemd.variables = [ "--all" ];
      extraConfig =
        if osConfig.networking.hostName == "alpha" then
          ''
            $monitor=DP-3
            $monitor2=HDMI-A-1

            # monitor=name,resolution,position,scale(,vrr,type)
            monitor=$monitor,1920x1080@165,auto,1,vrr,2 # DP, 165hz, can enable VRR on fullscreen (,vrr,2)
            monitor=$monitor2,preferred,auto-left,1

            workspace = 5, on-created-empty:[silent] $whatsapp
          ''
        else
          ''
            monitor = eDP-1,preferred,auto,1
            monitor = ,preferred,auto,1

            bind = ,XF86MonBrightnessDown, exec, brightnessctl s 5%-
            bind = ,XF86MonBrightnessUp, exec, brightnessctl s 5%+
          '';
      settings = {
        # GUI
        "$prefix" = "uwsm app --";

        "$browser" = "$prefix firefox";
        "$browser2" = "$prefix chromium-browser";
        "$whatsapp" = "webapp https://web.whatsapp.com";
        "$kiosk" = "$browser -P kiosk";
        "$discord" = "$prefix vesktop";
        "$GUIfileManager" = "$prefix nautilus";
        "$pomodoro" = "webapp https://noisekun.com/?theme=dark";
        "$showkeys" = "pkill wshowkeys || $prefix wshowkeys -a bottom -m 108 -b 00000066";
        "$screenshot" = "hyprshot -o ${config.xdg.userDirs.pictures}/ss -m";

        #"$emojimenu" = "bemoji -n";
        "$dmenu" = "rofi -show combi";

        "$showlayout" = "hdrop imv /home/repparw/src/totem/layout/totem.svg";

        "$lockscreen" = "loginctl lock-session";

        "$screenoff" = "sleep 3 && hyprctl dispatch dpms off";

        # Terminal
        "$terminal" = "$prefix foot";
        "$shell" = "fish";
        "$top" = "$terminal $shell -ic top";
        "$fileManager" = "$terminal --app-id filemanager $shell -ic yazi";
        "$spotify" = "$terminal --app-id spotify spotify_player";
        "$notes" = "$terminal --app-id obsinvim $shell -ic obsinvim";
        "$notes2" = "hdrop -c obsidian '$prefix obsidian'";

        # Autostart
        # Almost everything should use systemd services instead (see uwsm for autostart)
        # exec-once = [ ];

        general = {
          gaps_in = "1";
          gaps_out = "0";

          border_size = "1";

          # Set to true enable resizing windows by clicking and dragging on borders and gaps
          resize_on_border = false;

          allow_tearing = false;

          layout = "master";
        };

        plugin = {
          hyprsplit.num_workspaces = 9;
          hyprexpo = {
            workspace_method = "first 1";
          };
        };

        decoration = {
          # blur.enabled = false;
          # shadow.enabled = false;
          rounding = "14";
          dim_inactive = true;
          dim_strength = "0.1";
          active_opacity = "1";
          inactive_opacity = "1";
        };

        ecosystem = {
          no_donation_nag = true;
        };

        animations = {
          enabled = true;
        };

        dwindle = {
          pseudotile = true; # Master switch for pseudotiling
          preserve_split = true; # You probably want this
        };
        # master = { };

        misc = {
          force_default_wallpaper = "0";

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

        "$mod" = "SUPER";

        gesture = [
          "3, horizontal, workspace"
        ];

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

        bindl = [
          "$mod ALT, L, exec, $lockscreen; $screenoff"
          ", XF86AudioPlay, exec, playerctl play-pause"
          ", XF86AudioPause, exec, playerctl play-pause"
        ];

        bind = [
          "$mod, TAB, split:swapactiveworkspaces, current +1"
          "$mod SHIFT, TAB, focusmonitor,+1"

          "ALT, TAB, workspace, m+1"
          "ALT SHIFT, TAB, workspace, previous_per_monitor"

          ", mouse:276, hyprexpo:expo, on"

          "$mod, comma, exec, [float; noinitialfocus; noborder; center] $showlayout"
          "$mod, period, exec, $showkeys"

          "$mod, A, exec, $prefix anki"
          "$mod, C, exec, $whatsapp"
          "$mod, X, exec, $prefix io.github.alainm23.planify"
          "$mod, G, exec, webapp https://gemini.google.com/app"
          "$mod, RETURN, exec, $terminal"
          "$mod, W, killactive,"
          "$mod, M, exec, $spotify"
          "$mod, E, exec, $fileManager"
          "$mod, F, fullscreen"
          "$mod ALT, F, togglefloating"
          "$mod SHIFT, E, exec, $GUIfileManager"
          "$mod, SPACE, exec, $dmenu"
          "$mod SHIFT, SPACE, exec, $browser"
          "$mod, T, exec, $top"
          "$mod, Y, exec, [monitor $monitor2;noinitialfocus] $kiosk"
          "$mod, U, exec, $terminal --hold $shell -ic nrsu"
          "$mod, V, exec, [float; size 622 652; stayfocused; center] $terminal --app-id clipse clipse"
          "$mod, Z, exec, $prefix mpvclip"
          "$mod, N, exec, $notes"
          "$mod SHIFT, N, exec, $notes2"
          "$mod, R, exec, $terminal $shell -ic rpi"
          "$mod, B, exec, $prefix bttoggle"
          "$mod, S, exec, $prefix scrcpy -e -S"
          "$mod, P, exec, [monitor $monitor2;noinitialfocus] $pomodoro"

          ", Print, exec, $screenshot active -m output ## Active monitor"
          "$mod, Print, exec, $screenshot active -m window ## Active window"
          "Shift $mod, Print, exec, $screenshot region -zs ## Region"

          # Macropad churrosoft
          "CTRL ALT SHIFT, A, exec, $prefix steam"
          "CTRL ALT SHIFT, B, exec, obs-cmd recording toggle-pause"
          "CTRL ALT SHIFT, C, exec, obs-remux2wsp"
          "CTRL ALT SHIFT, D, exec, obs-cmd replay save"
          "CTRL ALT SHIFT, E, exec, hdrop $discord"
          "CTRL ALT SHIFT, F, exec, wpctl set-source-mute @DEFAULT_SOURCE@ toggle"
          # CTRL ALT SHIFT, G, exec,
          "CTRL ALT SHIFT, H, exec, $spotify"

          # Media keys
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

          "$mod, 1, split:workspace, 1"
          "$mod, 2, split:workspace, 2"
          "$mod, 3, split:workspace, 3"
          "$mod, 4, split:workspace, 4"
          "$mod, 5, split:workspace, 5"
          "$mod, 6, split:workspace, 6"
          "$mod, 7, split:workspace, 7"
          "$mod, 8, split:workspace, 8"
          "$mod, 9, split:workspace, 9"

          "$mod SHIFT, 1, split:movetoworkspace, 1"
          "$mod SHIFT, 2, split:movetoworkspace, 2"
          "$mod SHIFT, 3, split:movetoworkspace, 3"
          "$mod SHIFT, 4, split:movetoworkspace, 4"
          "$mod SHIFT, 5, split:movetoworkspace, 5"
          "$mod SHIFT, 6, split:movetoworkspace, 6"
          "$mod SHIFT, 7, split:movetoworkspace, 7"
          "$mod SHIFT, 8, split:movetoworkspace, 8"
          "$mod SHIFT, 9, split:movetoworkspace, 9"
        ];

        workspace = [
          "1, monitor:0, default:true"
          "w[tv1], gapsout:0, gapsin:0"
          "f[1], gapsout:0, gapsin:0"
        ];

        windowrule = [
          "noinitialfocus, initialClass:^(mpv)$"
          "noblur, initialClass:^(mpv)$"
          "nodim, initialClass:^(mpv)$"

          # Browser types
          "tag +chromium-based-browser, class:Chromium-browser"
          "tag +firefox-based-browser, class:firefox"

          "noblur, tag:firefox-based-browser"
          "opaque, tag:firefox-based-browser"
          "nodim, tag:firefox-based-browser"

          # Force chromium-based-browsers into a tile to deal with --app bug
          "tile, tag:chromium-based-browser"

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

          "noblur, class:^(.gamescope-wrapped)$"
          "nodim, class:^(.gamescope-wrapped)$"
          "maximize, class:^(.gamescope-wrapped)$"
          "immediate, class:^(.gamescope-wrapped)$"
          "content game, class:^(.gamescope-wrapped)$"

          "content game, class:^(steam_app_.*)$"

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
