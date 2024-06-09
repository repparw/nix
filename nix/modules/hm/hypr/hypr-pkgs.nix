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
	hyprpicker
	wl-clipboard

	# hyprwm/contrib
	inputs.hyprland-contrib.packages.${pkgs.system}.grimblast
	inputs.hyprland-contrib.packages.${pkgs.system}.hdrop
  	];

  programs.tofi = {
	enable = true;
	settings = {
	  font = "FiraCodeNerdFontMono-Regular"; # TODO hard code path with nix to this ttf so it's faster
	  font-size = 24;
	  text-color = "#d4be98";
	  selection-color = "#a9b665";
	  text-cursor-style = "bar";
	  prompt-text = "run: ";
	  placeholder-text = "";

	  output = "";
	  anchor = "center";
	  exclusive-zone = -1;

	  margin-top = 0;
	  margin-bottom = 0;
	  margin-left = 0;
	  margin-right = 0;

	  history = "true";

	  # theme

	  width = "100%";
	  height = "100%";
	  border-width = 0;
	  outline-width = 0;
	  padding-left = "35%";
	  padding-top = "35%";
	  result-spacing = 25;
	  num-results = 5;
	  background-color = "#000A";
	};

  };
}
