{ config, pkgs, unstable, inputs, stylix, ... }:
{
  imports = [
		../../modules/hm/hyprland.nix
		../../modules/hm/cli.nix
		../../modules/hm/nix.nix
		../../modules/hm/gui.nix
	#	../../modules/hm/gaming.nix
		];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.username = "repparw";
  home.homeDirectory = "/home/repparw";

  home.packages = with pkgs; [
  		# Essential packages
		nodejs # remove after porting nvim plugins to nix cfg

		docker-compose
		spotifyd
	]++[
	  unstable.obsidian
	];

  home.stateVersion = "23.11";

}
