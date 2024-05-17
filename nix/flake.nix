{


  description = "repparw's flake";

  inputs = {
	nixpkgs.url = "nixpkgs/nixpkgs-23.11"; # github:NixOS/nixpkgs/branch
	hyprland-nix.url = "github:hyprland-community/hyprnix";
  };
  outputs = { self, nixpkgs, ... }:
	let
		lib = nixpkgs.lib;
	in {
	  nixosConfigurations = {
		repparw = lib.nixosSystem {
		  system = "x86_64-linux";
		  modules = [
			./configuration.nix
		  ];
		};
	  };
  };

}
