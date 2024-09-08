{ ... }:
{
  "$monitor" = "DP-2";
  "$monitor2" = "HDMI-A-1";
  monitor = [
    # DP, 165hz, can enable VRR on fullscreen (,vrr,2)
    "$monitor,highrr,1920x0,1"
    "$monitor2,preferred,0x0,1"
  ];
  workspace = [
    "1, monitor=$monitor, default: true, persistent: true"
    "2, monitor=$monitor"
    "3, monitor=$monitor"
    "4, monitor=$monitor"
    "5, monitor=$monitor"

    "6, monitor=$monitor2, default: true"
    "7, monitor=$monitor2"
    "8, monitor=$monitor2"
    "9, monitor=$monitor2"
    "0, monitor=$monitor2"
  ];
  bind = [
    # Move active window to a workspace with mainMod + SHIFT + [0-9]
    "$mod SHIFT, 1, movewindow, mon:$monitor"
    "$mod SHIFT, 1, movetoworkspace, 1"
    "$mod SHIFT, 2, movewindow, mon:$monitor"
    "$mod SHIFT, 2, movetoworkspace, 2"
    "$mod SHIFT, 3, movewindow, mon:$monitor"
    "$mod SHIFT, 3, movetoworkspace, 3"
    "$mod SHIFT, 4, movewindow, mon:$monitor"
    "$mod SHIFT, 4, movetoworkspace, 4"
    "$mod SHIFT, 5, movewindow, mon:$monitor"
    "$mod SHIFT, 5, movetoworkspace, 5"

    "$mod SHIFT, 6, movewindow, mon:$monitor2"
    "$mod SHIFT, 6, movetoworkspace, 6"
    "$mod SHIFT, 7, movewindow, mon:$monitor2"
    "$mod SHIFT, 7, movetoworkspace, 7"
    "$mod SHIFT, 8, movewindow, mon:$monitor2"
    "$mod SHIFT, 8, movetoworkspace, 8"
    "$mod SHIFT, 9, movewindow, mon:$monitor2"
    "$mod SHIFT, 9, movetoworkspace, 9"
    "$mod SHIFT, 0, movewindow, mon:$monitor2"
    "$mod SHIFT, 0, movetoworkspace, 10"
  ];
  exec-once = [
    "jellyfin-mpv-shim"
    "[workspace 5 silent; fullscreen] $socials"
  ];
}
