{ inputs, config, lib, pkgs, unstable, ... }:

{
  home.packages = with pkgs; [
	# Desktop
	libdrm
	swaybg
	wlsunset
	wshowkeys
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
