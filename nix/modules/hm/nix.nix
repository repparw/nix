{ pkgs, ... }:

{
  home.packages = with pkgs; [
		# nix
		nh ## yet another nix helper
		manix # man for Nix
  	];
}

