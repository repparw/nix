{ ... }:

{
  imports = [
	./hypr-programs.nix
	./hypr-binds.nix
	./hypr-pkgs.nix
  ];

  wayland.windowManager.hyprland = {
	enable = true;
	settings = {
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
		exec-once = [
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
			resize_on_border = false;

			# Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
			allow_tearing = true;
			layout = "dwindle";
		};

		# https://wiki.hyprland.org/Configuring/Variables/#decoration
		decoration = {
			 rounding = "14";
			 drop_shadow = "1";
			 shadow_ignore_window = true;
			 shadow_offset = "7 7";
			 shadow_range = "15";
			 shadow_render_power = "4";
			 shadow_scale = "0.99";
			 "col.shadow" = "rgba(000000BB)";
			 #"col.shadow_inactive" = "rgba(000000BB)";
			 dim_inactive = true;
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
			  "workspaces, 1, 6, default"
			];
		};

		# See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
		dwindle = {
			pseudotile = true; # Master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
			preserve_split = true; # You probably want this
		};

		# See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
		master = {
			new_is_master = true;
		};

		# https://wiki.hyprland.org/Configuring/Variables/#misc
		misc = { 
			force_default_wallpaper = "0";
			disable_hyprland_logo = true;
		};
	  };
	};
}

