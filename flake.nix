{
  description = "repparw's flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      # url = "git+file:///home/repparw/code/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ndrop = {
      url = "github:Schweber/ndrop";
      flake = false;
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
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

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      commonModules = [
        { nixpkgs.config.allowUnfree = true; }
        inputs.nur.modules.nixos.default
        ./modules/nixos
        inputs.nix-index-database.nixosModules.nix-index
        { programs.nix-index-database.comma.enable = true; }
        ./secrets/nixos.nix
        inputs.home-manager.nixosModules.home-manager
        inputs.stylix.nixosModules.stylix
        (import ./overlays)
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
      };

      formatter.x86_64-linux = inputs.nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
    };
}
