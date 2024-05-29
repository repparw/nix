{ inputs, config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
	# Desktop
	libdrm
	unstable.hyprlock
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
