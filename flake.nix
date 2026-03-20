{
  description = "repparw's flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixpkgs-pr = {
      url = "github:GeoffreyFrogeye/nixpkgs/cfait";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
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

    den = {
      url = "github:vic/den";
    };

    import-tree = {
      url = "github:vic/import-tree";
    };

    flake-aspects = {
      url = "github:vic/flake-aspects";
    };
  };

  outputs =
    inputs:
    let
      eval = inputs.nixpkgs.lib.evalModules {
        modules = [
          (inputs.import-tree ./modules)
        ];
        specialArgs = {
          inherit inputs;
        };
      };
    in
    {
      nixosConfigurations = eval.config.flake.nixosConfigurations or { };

      packages.x86_64-linux =
        let
          alpha = eval.config.flake.nixosConfigurations.alpha.config.system.build;
          beta = eval.config.flake.nixosConfigurations.beta.config.system.build;
        in
        {
          vmAlpha = alpha.vm or null;
          vmBeta = beta.vm or null;
        }
        // (eval.config.flake.packages or { });

      apps.x86_64-linux =
        let
          alpha = eval.config.flake.nixosConfigurations.alpha.config.system.build;
          beta = eval.config.flake.nixosConfigurations.beta.config.system.build;
        in
        {
          vmAlpha = {
            program = "${alpha.vm}/bin/run-alpha-vm";
            name = "Run alpha in VM";
          };
          vmBeta = {
            program = "${beta.vm}/bin/run-beta-vm";
            name = "Run beta in VM";
          };
        }
        // (eval.config.flake.apps or { });

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
