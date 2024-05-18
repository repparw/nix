{

  description = "repparw's flake";

  inputs = {
	nixpkgs = {
	  url = "nixpkgs/nixpkgs-23.11"; # github:NixOS/nixpkgs/branch
	  config.allowUnfree = true;
	};
	nixpkgs-unstable.url = "nixpkgs/nixpkgs-unstable";
	hyprland-nix.url = "github:hyprland-community/hyprnix";
	home-manager = {
	  url = "github:nix-community/home-manager";
	  inputs.nixpkgs.follows = "nixpkgs";
	}
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
	let
		system = "x86_64-linux";
		pkgs = import nixpkgs { inherit system; };
		unstable = import nixpkgs-unstable { inherit system; };
	in {
	  nixosConfigurations = {
		repparw = nixpkgs.lib.nixosSystem {
		  inherit system;
		  modules = [
			./configuration.nix
			home-manager.nixosModules.home-manager
			{
			  home-manager.useUserPackages = true;
			  home-manager.users.repparw = homeManagerConfFor ./home.nix
			  home-manager.extraSpecialArgs = { inherit unstable; };
			}
		  ];
		};
	  };
  };

}
