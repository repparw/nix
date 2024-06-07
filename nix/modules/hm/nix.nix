{ inputs, config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
		# nix
		nil # nix lsp
		nh ## yet another nix helper
		manix # man for Nix
  	];
}

