{
  description = "repparw's flake";

  outputs = { self, ... }@inputs:
	let

		system = "x86_64-linux";

		pkgs = inputs.nixpkgs.legacyPackages.${system};
		unstable = inputs.nixpkgs-unstable.legacyPackages.${system};

	in {
	  nixosConfigurations = {
		beta = inputs.nixpkgs.lib.nixosSystem {
		  modules = [
			/home/repparw/nix/hosts/beta/configuration.nix
			inputs.stylix.nixosModules.stylix { image = "/home/repparw/Pictures/gruvbox.jpg"; }
			inputs.home-manager.nixosModules.home-manager
			];
		  specialArgs = {
			inherit system;
			inherit pkgs;
			inherit unstable; 
			inherit inputs;
		  };
		};
	  };
  };

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

}
