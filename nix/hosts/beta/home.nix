{ pkgs, unstable, ... }:
{
  imports = [
		../../modules/hm/cli.nix
		../../modules/hm/nix.nix
		../../modules/hm/hypr/hyprland.nix
		../../modules/hm/gui.nix
		];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.username = "repparw";
  home.homeDirectory = "/home/repparw";

  home.packages = with pkgs; [
  		# Essential packages
		nodejs # remove after porting nvim plugins to nix cfg

		docker-compose
	]++[
	  unstable.obsidian
	];

  home.stateVersion = "23.11";

}
