{
  description = "repparw's flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      # url = "git+file:///home/repparw/code/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
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

    firefox-addons = {
      url = "github:petrkozorezov/firefox-addons-nix";
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

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      commonModules = [
        { nixpkgs.config.allowUnfree = true; }
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
          users.repparw = {
            imports = [
              ./modules/hm
              ./home/${hostname}.nix
              inputs.noctalia.homeModules.default
            ];
          };
        };
      };

      mkSystem =
        hostname: extraModules:
        inputs.nixpkgs.lib.nixosSystem {
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

      packages.x86_64-linux = {
        vmAlpha = (mkSystem "alpha" [ ]).config.system.build.vm;
        vmBeta = (mkSystem "beta" [ ]).config.system.build.vm;
      };

      apps.x86_64-linux = {
        vmAlpha = {
          program = "${(mkSystem "alpha" [ ]).config.system.build.vm}/bin/run-alpha-vm";
          name = "Run alpha in VM";
        };
        vmBeta = {
          program = "${(mkSystem "beta" [ ]).config.system.build.vm}/bin/run-beta-vm";
          name = "Run beta in VM";
        };
      };

      formatter.x86_64-linux =
        let
          pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
        in
        pkgs.treefmt.withConfig {
          runtimeInputs = with pkgs; [
            nixfmt
            deadnix
          ];
          settings = {
            on-unmatched = "info";
            formatter.nixfmt = {
              command = "nixfmt";
              includes = [ "*.nix" ];
            };
            formatter.deadnix = {
              command = "deadnix";
              options = [
                "--edit"
                "--no-lambda-arg"
                "--no-lambda-pattern-names"
              ];
              includes = [ "*.nix" ];
            };
          };
        };
    };
}
