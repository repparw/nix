{
  description = "repparw's flake";
  inputs = {
    nixvim.url = "github:nix-community/nixvim";
    agenix.url = "github:ryantm/agenix";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    home-manager.url = "github:nix-community/home-manager"; # Branches for stable, master follows unstable
    nix-index-database.url = "github:nix-community/nix-index-database";
    nur.url = "github:nix-community/NUR";
  };

  outputs = {home-manager, ...} @ inputs: let
    # Base modules configuration for all systems
    mkModules = hostname: [
      # Adds the NUR overlay
      inputs.nur.modules.nixos.default
      # NUR modules to import
      ./systems/common.nix
      ./systems/${hostname}
      inputs.nix-index-database.nixosModules.nix-index
      inputs.agenix.nixosModules.default
      home-manager.nixosModules.home-manager
      {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "hm-backup";
          extraSpecialArgs = {
            inherit inputs;
          };
          users.repparw = {
            imports = [
              ./home/common
              ./home/${hostname}
              inputs.nixvim.homeManagerModules.nixvim
            ];
          };
        };
      }
    ];
  in {
    nixosConfigurations = {
      alpha = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = mkModules "alpha";
        specialArgs = {
          inherit inputs;
        };
      };

      beta = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = mkModules "beta";
        specialArgs = {
          inherit inputs;
        };
      };

      iso = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules =
          [
            "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            (
              {...}: {
                isoImage.squashfsCompression = "gzip -Xcompression-level 1";
              }
            )
          ]
          ++ (mkModules "beta");
        specialArgs = {
          inherit inputs;
        };
      };
    };
  };
}
