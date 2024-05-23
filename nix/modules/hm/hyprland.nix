{ inputs, config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
	# Desktop
	libdrm
	swaylock
	swayidle
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
