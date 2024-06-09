{
  description = "repparw's flake";

  outputs = { self, home-manager, stylix, ... }@inputs:
	let

		system = "x86_64-linux";
		systemSettings = {
				hostName = "beta";
		};

		pkgs = import inputs.nixpkgs { inherit system; config.allowUnfree = true; };
		unstable = import inputs.nixpkgs-unstable { inherit system; config.allowUnfree = true; };

	in {
	  nixosConfigurations = {
		beta = inputs.nixpkgs.lib.nixosSystem {
		  modules = [
			./hosts/${systemSettings.hostName}/configuration.nix
#			inputs.stylix.nixosModules.stylix
			home-manager.nixosModules.home-manager
			({config, ...}: {
			  home-manager.useGlobalPkgs = true;
			  home-manager.useUserPackages = true;
			  home-manager.backupFileExtension = "bak";
			  home-manager.extraSpecialArgs = {
				inherit unstable; 
				inherit inputs;
			    inherit (config.networking) hostName;
			  };
			  home-manager.users.repparw = import ./hosts/${systemSettings.hostName}/home.nix;
			})
			];
			};
		  specialArgs = {
			inherit unstable; 
			inherit inputs;
		  };
		};
	  };

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-24.05";
    };
	nixpkgs-unstable = {
      url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    };
    hyprland-contrib = {
      url = "github:hyprwm/contrib";
    };
    stylix = {
      url = "github:danth/stylix";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05"; # Branches for stable, master follows unstable
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

}
