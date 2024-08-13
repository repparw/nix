{ pkgs, unstable, ... }:
{
  imports = [
		../../modules/hm/cli.nix
		../../modules/hm/nix.nix
		../../modules/hm/gui.nix
		../../modules/hm/hypr/hypr-pkgs.nix
		../../modules/hm/gaming.nix
		];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.username = "repparw";
  home.homeDirectory = "/home/repparw";

  home.packages = with pkgs; [
  		# Essential packages
		jellyfin-mpv-shim
	]++[
	  unstable.obsidian
	];

  home.stateVersion = "23.11";
}
