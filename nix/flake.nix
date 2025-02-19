{
  description = "repparw's flake";

  outputs =
    {
      home-manager,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      stable = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # Base modules configuration for all systems
      mkModules = hostname: [
        ./hosts/common.nix
        ./hosts/${hostname}
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "hm-backup";
            extraSpecialArgs = {
              inherit stable inputs;
            };
            users.repparw = {
              imports = [
                ./home/common
                ./home/${hostname}
              ];
            };
          };
        }
      ];

    in
    {
      nixosConfigurations = {
        alpha = inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = mkModules "alpha";
          specialArgs = {
            inherit stable inputs;
          };
        };

        beta = inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = mkModules "beta";
          specialArgs = {
            inherit stable inputs;
          };
        };

        iso = inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            (
              { ... }:
              {
                isoImage.squashfsCompression = "gzip -Xcompression-level 1";
              }
            )
          ] ++ (mkModules "beta");
          specialArgs = {
            inherit stable inputs;
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
      url = "github:NixOS/nixpkgs/nixos-24.11";
    };
    home-manager = {
      url = "github:nix-community/home-manager"; # Branches for stable, master follows unstable
    };
  };

}
