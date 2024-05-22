{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
	# Desktop
	swaylock
	swayidle
	swaynotificationcenter
	waybar
	tofi
	hyprpicker
	wl-clipboard
	# hyprwm/contrib
	inputs.hyprland-contrib.packages.${pkgs}.grimblast
	inputs.hyprland-contrib.packages.${pkgs}.hdrop
  	];
}
