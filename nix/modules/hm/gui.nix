
{ pkgs, ... }:

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
		zathura
		vesktop
		spotifyd
		spotify-player
		obs-studio
		waydroid
		scrcpy
		# find pomo app in nixpkgs
  	];

  programs.feh = {
	enable = true;
	buttons = {
	  zoom_in = 4;
	  zoom_out = 5;
	};
	keybindings = {
	  prev_img = "comma";
	  next_img = "period";
	};
  };

# systemd.user.services = { // TODO Migrate OBS and spotifyd
	
	

}
