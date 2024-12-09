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

      # Helper function to create a NixOS configuration
      mkSystem =
        hostname:
        inputs.nixpkgs.lib.nixosSystem {
          modules = [
            # Host-specific configuration
            ./hosts/${hostname}
            # Home-manager configuration
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "hm-backup";
                extraSpecialArgs = {
                  inherit stable inputs;
                };
                users.repparw = import ./home/${hostname};
              };
            }
          ];
          specialArgs = {
            inherit stable inputs;
          };
        };

    in
    {
      nixosConfigurations = {
        alpha = mkSystem "alpha";
        beta = mkSystem "beta";
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
      url = "github:NixOS/nixpkgs/nixos-24.11";
    };
    home-manager = {
      url = "github:nix-community/home-manager"; # Branches for stable, master follows unstable
    };
  };

}
