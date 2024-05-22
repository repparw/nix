{

  description = "repparw's flake";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-23.11"; # Modification: Correct URL syntax
    };
	nixpkgs-unstable = {
      url = "github:NixOS/nixpkgs/nixpkgs-unstable"; # Modification: Correct URL syntax
    };
    hyprland-nix = {
      url = "github:hyprland-community/hyprnix";
    };
    stylix = {
      url = "github:danth/stylix";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, ... }@inputs:
	let
		system = "x86_64-linux";
		pkgs = nixpkgs.legacyPackages.${system};
		unstable = nixpkgs-unstable.legacyPackages.${system};
	in {
	  nixosConfigurations = {
		beta = nixpkgs.lib.nixosSystem {
		  extraSpecialArgs = { inherit inputs; };
		  modules = [
			stylix.nixosModules.stylix { image = "/home/repparw/Pictures/gruvbox.jpg"; }
			hyprland-nix.nixosModules.hyprland-nix { enable = true; }
			home-manager.nixosModules.home-manager
			./hosts/default/configuration.nix
			];
		};
	  };
  };

}
