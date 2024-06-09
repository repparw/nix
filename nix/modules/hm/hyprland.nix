{ inputs, config, lib, pkgs, unstable, ... }:

{
  wayland.windowManager.hyprland = {
	enable = true;
	package = unstable.hyprland;
	xwayland.enable = true;
	systemd.enable = true;
	settings = {

	};
  };

  home.packages = with pkgs; [
	# Desktop
	libdrm
	swaybg
	wlsunset
	hyprlock
	swayidle # unstable.hypridle?
	swaynotificationcenter
	waybar
	tofi
	hyprpicker
	wl-clipboard
	# hyprwm/contrib
	inputs.hyprland-contrib.packages.${pkgs.system}.grimblast
	inputs.hyprland-contrib.packages.${pkgs.system}.hdrop
  	];
}
