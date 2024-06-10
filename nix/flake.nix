{
  description = "repparw's flake";

  outputs = { self, home-manager, stylix, ... }@inputs:
	let

		system = "x86_64-linux";

		unstable = import inputs.nixpkgs-unstable { inherit system; config.allowUnfree = true; };

	in {
	  nixosConfigurations = {

		alpha = inputs.nixpkgs.lib.nixosSystem {
		  modules = [
#			inputs.stylix.nixosModules.stylix
			./hosts/default.nix
			./modules/nixos/cachix.nix
			./modules/nixos/common.nix
			home-manager.nixosModules.home-manager {
			  home-manager.useGlobalPkgs = true;
			  home-manager.useUserPackages = true;
			  home-manager.backupFileExtension = "hm-backup";
			  home-manager.extraSpecialArgs = {
				hostName = "alpha";
				inherit unstable; 
				inherit inputs;
			  };
			  home-manager.users.repparw = import ./hosts/alpha/home.nix;
			}
			];
			specialArgs = {
			  hostName = "alpha";
			  inherit unstable; 
			  inherit inputs;
			};
			};

		beta = inputs.nixpkgs.lib.nixosSystem {
		  modules = [
#			inputs.stylix.nixosModules.stylix
			  ./hosts/default.nix
			  ./modules/nixos/cachix.nix
			  ./modules/nixos/common.nix
			  home-manager.nixosModules.home-manager {
				home-manager.useGlobalPkgs = true;
				home-manager.useUserPackages = true;
				home-manager.backupFileExtension = "hm-backup";
				home-manager.extraSpecialArgs = {
				  hostName = "beta";
				  inherit unstable; 
				  inherit inputs;
				};
				home-manager.users.repparw = import ./hosts/beta/home.nix;
			  }
		  ];
		  specialArgs = {
			hostName = "beta";
			inherit unstable; 
			inherit inputs;
		  };
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
