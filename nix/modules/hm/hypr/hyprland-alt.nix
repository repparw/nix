{ pkgs, hostName, ... }:

let
  # alpha equals true if hostname is alpha, else false
  alpha = (hostName == "alpha");
in
{
  wayland.windowManager.hyprland = {
	enable = true;
	package = pkgs.hyprland;
	xwayland.enable = true;
	systemd.enable = true;
	extraConfig = ''
	  ${builtins.readFile ./hyprland.conf}
	  ${if alpha then builtins.readFile ./binds-alpha.conf else builtins.readFile ./binds-beta.conf}
	'';
	};
}
