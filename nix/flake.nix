{
  description = "repparw's flake";

  outputs = { self, home-manager, stylix, ... }@inputs:
	let

		system = "x86_64-linux";
		systemSettings = {
				hostName = "beta";
		};

		pkgs = import inputs.nixpkgs { inherit system; config.allowUnfree = true; };
		stable = import inputs.nixpkgs-stable { inherit system; config.allowUnfree = true; };

	in {
	  nixosConfigurations = {
		beta = inputs.nixpkgs.lib.nixosSystem {
		  modules = [
			./hosts/${systemSettings.hostName}/configuration.nix
#			inputs.stylix.nixosModules.stylix
			home-manager.nixosModules.home-manager {
			  home-manager.useGlobalPkgs = true;
			  home-manager.useUserPackages = true;
			  home-manager.backupFileExtension = "bak";
			  home-manager.users.repparw = import ./hosts/${systemSettings.hostName}/home.nix;
			  home-manager.extraSpecialArgs = {
				inherit system;
				inherit pkgs;
				inherit stable; 
				inherit inputs;
			  };
			}
			];
		  specialArgs = {
			inherit system;
			inherit pkgs;
			inherit stable; 
			inherit inputs;
		  };
		};
	  };
  };

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixpkgs-unstable"; # Modification: Correct URL syntax
    };
	nixpkgs-stable = {
      url = "github:NixOS/nixpkgs/nixos-23.11"; # Modification: Correct URL syntax
    };
    hyprland-nix = {
      url = "github:hyprland-community/hyprnix"; # Follows unstable
    };
	hyprland-contrib = {
	  url = "github:hyprwm/contrib";
	};
    stylix = {
      url = "github:danth/stylix";
    };
    home-manager = {
      url = "github:nix-community/home-manager"; # Follows unstable, has branches for stable
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

}
