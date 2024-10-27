{ osConfig, ... }:

{
  imports = [ ./hypr-pkgs.nix ];
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.variables = [ "--all" ];
    ${
      if osConfig.networking.hostName == "alpha" then "extraConfig" else null
    } = builtins.readFile ../../source/hyprland-alpha.conf;
    ${
      if osConfig.networking.hostName != "alpha" then "extraConfig" else null
    } = builtins.readFile ../../source/hyprland-not-alpha.conf;
    settings = {
      env = [
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        "XDG_SCREENSHOTS_DIR,$HOME/Pictures/ss"
      ];

      # GUI
      "$browser" = "firefox";
      "$socials" = "$browser -P socials";
      "$kiosk" = "$browser -P kiosk";
      "$browser2" = "chromium-browser";
      "$discord" = "vesktop";
      "$GUIfileManager" = "nautilus";
      "$pomodoro" = "pomatez";
      "$showkeys" = "wshowkeys -a bottom -m 108 -b 00000066";
      "$screenshot" = "hyprshot -o $XDG_SCREENSHOTS_DIR -m";
      "$desktopmenu" = "killall tofi-drun || tofi-drun";
      "$cmdmenu" = "killall tofi-run || tofi-run | xargs hyprctl dispatch exec --";
      "$notificationsDaemon" = "swaync";

      "$lockscreen" = "loginctl lock-session";

      "$screenoff" = "sleep 3 && hyprctl dispatch dpms off";

      # Terminal
      "$terminal" = "kitty";
      "$top" = "$terminal btm --theme gruvbox";
      "$fileManager" = "LS_COLORS='di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43' hdrop $terminal --class filemanager zsh -c lf";
      "$spotify" = "$terminal --class spotify spotify_player";
      "$notes" = "hdrop -c obsinvim '$terminal --class obsinvim zsh -ic /home/repparw/.config/scripts/obsinvim'";

      # Autostart
      exec-once = [
        "swaybg -i ~/Pictures/gruvbox.jpg"
        "/usr/libexec/kf6/polkit-kde-authentication-agent-1" # TODO WARN probably doesnt work? make systemd service
        "$notificationsDaemon"
      ];

      general = {
        gaps_in = "1";
        gaps_out = "0";

        border_size = "1";

        # https://wiki.hyprland.org/Configuring/Variables/#variable-types for info about colors
        "col.active_border" = "rgba(D4BE98FF)";
        "col.inactive_border" = "rgba(ebdbb211)";

        # Set to true enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = "false";

        # Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
        allow_tearing = "false";

        layout = "dwindle";
      };

      # https://wiki.hyprland.org/Configuring/Variables/#decoration
      decoration = {
        rounding = "14";
        drop_shadow = "1";
        shadow_ignore_window = "true";
        shadow_offset = "7 7";
        shadow_range = "15";
        shadow_render_power = "4";
        shadow_scale = "0.99";
        "col.shadow" = "rgba(000000BB)";
        #"col.shadow_inactive" = "rgba(000000BB)";
        dim_inactive = "true";
        dim_strength = "0.1";
        active_opacity = "1";
        inactive_opacity = "1";
        # Your blur "amount" is blur_size * blur_passes, but high blur_size (over around 5-ish) will produce artifacts.
        # if you want heavy blur, you need to up the blur_passes.
        # the more passes, the more you can up the blur_size without noticing artifacts.
      };

      # https://wiki.hyprland.org/Configuring/Variables/#animations
      animations = {
        enabled = true;

        # Default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more

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

      # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
      dwindle = {
        pseudotile = "true"; # Master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
        preserve_split = "true"; # You probably want this
      };

      # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more

      # https://wiki.hyprland.org/Configuring/Variables/#misc
      misc = {
        force_default_wallpaper = "0";
        disable_hyprland_logo = "true";

        key_press_enables_dpms = true; # mouse_move is false by default
      };

      ## keybinds

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

      bindr = [
        "$mod, SUPER_L, exec, $desktopmenu"
        "$mod ALT, SUPER_L, exec, $cmdmenu"
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
      bindl = [ "$mod ALT, L, exec, $lockscreen; $screenoff" ];
      bind = [
        "$mod, X, focusmonitor,+1 "
        "SHIFT $mod, X, movewindow,mon:+1"
        "$mod, comma, movecurrentworkspacetomonitor,l"
        "$mod, period, movecurrentworkspacetomonitor,r"

        # Scroll through monitor active workspaces with mainMod + scroll
        "$mod, C, workspace, m+1"
        "$mod SHIFT, C, workspace, previous_per_monitor"

        ", mouse:276, workspace, m+1"

        "$mod, RETURN, exec, $terminal"
        "$mod, W, killactive,"
        "$mod, M, exec, hdrop $spotify"
        "$mod SHIFT, M, exec, ytfzf -D"
        "$mod, E, exec, $fileManager"
        "$mod, F, fullscreen"
        "$mod SHIFT, F, fullscreen, 2"
        "$mod ALT, F, togglefloating"
        "$mod SHIFT, E, exec, $GUIfileManager"
        "$mod, SPACE, exec, $browser"
        "$mod ALT, SPACE, exec, $socials"
        "$mod SHIFT, SPACE, exec, $browser2"
        "$mod, T, exec, $top"
        "$mod, Y, exec, [workspace 6 silent;noinitialfocus] $kiosk"
        "$mod, U, exec, ~/.config/scripts/update"
        "$mod, V, exec, ~/.config/scripts/jelly"
        "$mod, Z, exec, ~/.config/scripts/mpvclip"
        "$mod, N, exec, $notes"
        "$mod, R, exec, $terminal zsh -ic rpi"
        "$mod, B, exec, ~/.config/scripts/bttoggle"
        "$mod, P, exec, [workspace 6 silent;float;size 5% 3%;move 79% 2%] hdrop $pomodoro"

        "$mod, G, exec, xdg-open https://mail.google.com"

        ", Print, exec, $screenshot active -m output ## Active monitor"
        "$mod, Print, exec, $screenshot active -m window ## Active window"
        "Shift $mod, Print, exec, $screenshot region -z ## Region"

        "$mod, O, exec, wl-paste | tesseract - stdout | wl-copy ## OCR"
        "$mod, Q, exec, wl-paste --type image/png | zbarimg --raw - | wl-copy ## OCR"

        # Macropad
        "CTRL ALT SHIFT, A, exec, hdrop steam"
        "CTRL ALT SHIFT, B, exec, obs-cmd recording toggle-pause"
        "CTRL ALT SHIFT, C, exec, ~/.config/scripts/obs_last_remux2wsp"
        "CTRL ALT SHIFT, D, exec, obs-cmd replay save"
        "CTRL ALT SHIFT, E, exec, hdrop $discord"
        "CTRL ALT SHIFT, F, exec, pactl set-source-mute @DEFAULT_SOURCE@ toggle"
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

        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"

        # Example special workspace (scratchpad)
        "$mod, S, togglespecialworkspace, magic"
        "$mod SHIFT, S, movetoworkspace, special:magic"

        # Scroll through monitor active workspaces with mainMod + scroll
        "$mod, mouse_down, workspace, m+1"
        "$mod, mouse_up, workspace, m-1"
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

        "suppressevent maximize, class:.*"

        "nodim, class:^(cs2)$"
        "noblur, class:^(cs2)$"
        "maximize, class:^(cs2)$"
        "immediate, class:^(cs2)$"

        "float, title:^(Picture-in-Picture|Picture in picture)$"
        "monitor 0, title:^(Picture-in-Picture|Picture in picture)$"
        "move 100%-w-25 100%-w-0, title:^(Picture-in-Picture|Picture in picture)$"
        "size 400 225, title:^(Picture-in-Picture|Picture in picture)$"
        "pin, title:^(Picture-in-Picture|Picture in picture)$"

      ];

    };
  };

}
