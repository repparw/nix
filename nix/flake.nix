{
  description = "repparw's flake";

  outputs =
    {
      home-manager,
      ...
    }@inputs:
    let

      system = "x86_64-linux";

      stable = import inputs.nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };

    in
    {
      nixosConfigurations = {

        alpha = inputs.nixpkgs.lib.nixosSystem {
          modules = [
            ./hosts/alpha
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "hm-backup";
              home-manager.extraSpecialArgs = {
                inherit stable;
                inherit inputs;
              };
              home-manager.users.repparw = import ./home/alpha;
            }
          ];
          specialArgs = {
            inherit stable;
            inherit inputs;
          };
        };

        beta = inputs.nixpkgs.lib.nixosSystem {
          modules = [
            ./hosts/beta
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "hm-backup";
              home-manager.extraSpecialArgs = {
                inherit stable;
                inherit inputs;
              };
              home-manager.users.repparw = import ./home/beta;
            }
          ];
          specialArgs = {
            inherit stable;
            inherit inputs;
          };
        };

      };

    };

  inputs = {
    nixvim = {
      url = "github:repparw/nixvim/main";
    };
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
    stable = {
      url = "github:NixOS/nixpkgs/nixos-24.05";
    };
    home-manager = {
      url = "github:nix-community/home-manager"; # Branches for stable, master follows unstable
    };
  };

}
