{ inputs, config, lib, pkgs, ... }:

{
  imports = [
	./hypr-programs.nix
	./hypr-binds.nix
	./hypr-pkgs.nix
  ];

  wayland.windowManager.hyprland = {
	enable = true;
	package = unstable.hyprland;
	xwayland.enable = true;
	systemd.enable = true;
	settings = {
	  mkMerge [{
	  (lib.mkIf (lib.equalStrings config.system.build.hostName "alpha") {[
		"$monitor" = "DP-2";
		"$monitor2" = "HDMI-A-1";
		monitor = [
		  # DP, 165hz, can enable VRR on fullscreen (,vrr,2)
		  "$monitor,highrr,1920x0,1"
		  "$monitor2,preferred,0x0,1"
		];
        workspace = [
		  "1, monitor=$monitor, default: true"
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
		windowrulev2 = [
		  "monitor $display2,class:^(mpv)$"
		  "noinitialfocus,class:^(mpv)$"
		  "noblur,class:^(mpv)$"
		  "fullscreen,class:^(mpv)$"

		  "noblur,class:^(org.mozilla.firefox)$"
		  "opaque,class:^(org.mozilla.firefox)$"
		  "nodim,class:^(org.mozilla.firefox)$"

		  "noborder, onworkspace:w[t1]"

		  "suppressevent maximize, class:.* # You'll probably like this."

		  "immediate, class:^(cs2)$"
		];
		bind = [
		  # Switch workspaces with mainMod + [0-9]
		  "$mod, 1, focusmonitor, $display"
		  "$mod, 1, workspace, 1"
		  "$mod, 2, focusmonitor, $display"
		  "$mod, 2, workspace, 2"
		  "$mod, 3, focusmonitor, $display"
		  "$mod, 3, workspace, 3"
		  "$mod, 4, focusmonitor, $display"
		  "$mod, 4, workspace, 4"
		  "$mod, 5, focusmonitor, $display"
		  "$mod, 5, workspace, 5"
		  "$mod, 6, focusmonitor, $display2"
		  "$mod, 6, workspace, 6"
		  "$mod, 7, focusmonitor, $display2"
		  "$mod, 7, workspace, 7"
		  "$mod, 8, focusmonitor, $display2"
		  "$mod, 8, workspace, 8"
		  "$mod, 9, focusmonitor, $display2"
		  "$mod, 9, workspace, 9"
		  "$mod, 0, focusmonitor, $display2"
		  "$mod, 0, workspace, 10"

		  # Move active window to a workspace with mainMod + SHIFT + [0-9]
		  "$mod SHIFT, 1, movewindow, mon:$display"
		  "$mod SHIFT, 1, movetoworkspace, 1"
		  "$mod SHIFT, 2, movewindow, mon:$display"
		  "$mod SHIFT, 2, movetoworkspace, 2"
		  "$mod SHIFT, 3, movewindow, mon:$display"
		  "$mod SHIFT, 3, movetoworkspace, 3"
		  "$mod SHIFT, 4, movewindow, mon:$display"
		  "$mod SHIFT, 4, movetoworkspace, 4"
		  "$mod SHIFT, 5, movewindow, mon:$display"
		  "$mod SHIFT, 5, movetoworkspace, 5"

		  "$mod SHIFT, 6, movewindow, mon:$display2"
		  "$mod SHIFT, 6, movetoworkspace, 6"
		  "$mod SHIFT, 7, movewindow, mon:$display2"
		  "$mod SHIFT, 7, movetoworkspace, 7"
		  "$mod SHIFT, 8, movewindow, mon:$display2"
		  "$mod SHIFT, 8, movetoworkspace, 8"
		  "$mod SHIFT, 9, movewindow, mon:$display2"
		  "$mod SHIFT, 9, movetoworkspace, 9"
		  "$mod SHIFT, 0, movewindow, mon:$display2"
		  "$mod SHIFT, 0, movetoworkspace, 10"
		];
	  ];
	  });
	  # !alpha
	  (lib.mkIf !(lib.equalStrings config.system.build.hostName "alpha") {[
		monitor = ",preferred,auto,1";
		bind = [
		  # Switch workspaces with mainMod + [0-9]
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

		  # Move active window to a workspace with mainMod + SHIFT + [0-9]
		  "$mod SHIFT, 1, movetoworkspace, 1"
		  "$mod SHIFT, 2, movetoworkspace, 2"
		  "$mod SHIFT, 3, movetoworkspace, 3"
		  "$mod SHIFT, 4, movetoworkspace, 4"
		  "$mod SHIFT, 5, movetoworkspace, 5"

		  "$mod SHIFT, 6, movetoworkspace, 6"
		  "$mod SHIFT, 7, movetoworkspace, 7"
		  "$mod SHIFT, 8, movetoworkspace, 8"
		  "$mod SHIFT, 9, movetoworkspace, 9"
		  "$mod SHIFT, 0, movetoworkspace, 10"
		];

	  ];
	  });
	  # SHARED CONFIG
	  env = [
		 "XCURSOR_SIZE,24"
	     "HYPRCURSOR_SIZE,24"
         "XDG_SCREENSHOTS_DIR,$HOME/Pictures/ss"
	  ];

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
	  # Autostart
	  exec-once = [
		"swaybg -i ~/Pictures/gruvbox.jpg"
		"wlsunset -l -34.9 -L -57.9"
		"/usr/libexec/kf6/polkit-kde-authentication-agent-1" # TODO WARN probably doesnt work? make systemd service 
		"$notificationsDaemon"
		"waybar"
		"jellyfin-mpv-shim"
		"kdeconnectd" # check if working
		"[monitor $display;workspace 5 silent] $socials"
	  ];

	  general = { 
		  gaps_in = "1";
		  gaps_out = "0";

		  border_size = "1";

		  # https://wiki.hyprland.org/Configuring/Variables/#variable-types for info about colors
		  "col.active_border" = "rgba(D4BE98FF)";
		  "col.inactive_border" = "rgba(ebdbb211)";

		  cursor_inactive_timeout = "2";

		  # Set to true enable resizing windows by clicking and dragging on borders and gaps
		  resize_on_border = "false";

		  # Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
		  allow_tearing = "true";
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
		  enabled = true

		  # Default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more

		  bezier = myBezier, 0.05, 0.9, 0.1, 1.05

		  animation = [
			"windows, 1, 7, myBezier"
			"windowsOut, 1, 7, default, popin 80%"
			"border, 1, 10, default"
			"borderangle, 1, 8, default"
			"fade, 1, 7, default"
			"workspaces, 1, 6, default"
		  ];
	  };

	  # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
	  dwindle = {
		  pseudotile = "true"; # Master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
		  preserve_split = "true"; # You probably want this
	  };

	  # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
	  master = {
		  new_is_master = "true";
	  };

	  # https://wiki.hyprland.org/Configuring/Variables/#misc
	  misc = { 
		  force_default_wallpaper = "0";
		  disable_hyprland_logo = "true";
	  };
	
	}];
  };

}
