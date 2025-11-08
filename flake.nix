{
  description = "repparw's flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    nixvim-config = {
      url = "github:repparw/nixvim-config";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jovian = {
      url = "github:jovian-experiments/jovian-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      commonModules = [
        (import ./overlays { inherit inputs; })
        inputs.nur.modules.nixos.default
        ./modules/nixos
        inputs.nix-index-database.nixosModules.nix-index
        { programs.nix-index-database.comma.enable = true; }
        ./secrets/nixos.nix
        inputs.home-manager.nixosModules.home-manager
        inputs.stylix.nixosModules.stylix
      ];

      mkHomeManager = hostname: {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "hm-backup";
          extraSpecialArgs = {
            inherit inputs;
          };
          users.repparw = {
            imports = [
              ./modules/hm
              ./home/${hostname}.nix
            ];
          };
        };
      };

      mkSystem =
        hostname: extraModules:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules =
            commonModules
            ++ [
              ./systems/${hostname}
              (mkHomeManager hostname)
            ]
            ++ extraModules;
          specialArgs = {
            inherit inputs;
          };
        };
    in
    {
      nixosConfigurations = {
        alpha = mkSystem "alpha" [ ];
        beta = mkSystem "beta" [ ];
        # delta = mkSystem "delta" [ inputs.jovian.nixosModules.default ];
      };
    };
}
