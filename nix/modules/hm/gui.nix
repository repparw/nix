
{ inputs, config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
		# GUI
		kitty
		firefox
		chromium
		jellyfin-mpv-shim
		mpv
		mpvScripts.mpris
		mpvScripts.mpv-webm
		mpvScripts.quality-menu
		feh
		zathura
		vesktop
		spotify-player
		obs-studio
		waydroid
		scrcpy
		# find pomo app in nixpkgs
  	];
}
