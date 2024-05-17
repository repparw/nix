{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
  		# Desktop
  		swaylock
  		swayidle
  		waybar
  		tofi
		hyprpicker
		wl-clipboard
		# hyprwm/contrib
		inputs.hyprland-contrib.packages.${pkgs.system}.grimblast
		inputs.hyprland-contrib.packages.${pkgs.system}.hdrop
  	];

  ]
}
