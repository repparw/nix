{ inputs, pkgs, ... }:

{
  home.packages = with pkgs; [
	# Desktop
	libdrm
	swaybg
	wlsunset
	wshowkeys
	hyprlock
	swayidle # unstable.hypridle?
	mako # dunst alt
	swaynotificationcenter
	tofi
	waybar
	hyprpicker
	wl-clipboard

	# hyprwm/contrib
	inputs.hyprland-contrib.packages.${pkgs.system}.grimblast
	inputs.hyprland-contrib.packages.${pkgs.system}.hdrop
  	];

}
