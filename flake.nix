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

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
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
      flake = inputs.flake-parts.lib.mkFlake { inherit inputs; } {
        systems = [ "x86_64-linux" ];
        imports = [
          (inputs.import-tree ./modules)
        ];
      };

      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
      nixosConfigurations = flake.nixosConfigurations or { };
      alpha = nixosConfigurations.alpha.config.system.build;
      beta = nixosConfigurations.beta.config.system.build;
    in
    flake
    // {
      formatter.x86_64-linux = pkgs.treefmt.withConfig {
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

      packages.x86_64-linux = {
        vmAlpha = alpha.vm or null;
        vmBeta = beta.vm or null;
      };

      apps.x86_64-linux = {
        vmAlpha = {
          type = "app";
          program = "${alpha.vm}/bin/run-alpha-vm";
        };
        vmBeta = {
          type = "app";
          program = "${beta.vm}/bin/run-beta-vm";
        };
      };
    };
}
