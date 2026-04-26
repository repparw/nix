{ inputs, ... }:
{
  flake-file.inputs = {
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };

    nixvim-config = {
      url = "github:repparw/nixvim-config";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
        nixvim.follows = "nixvim";
      };
    };
  };

  den.aspects.nixvim = {
    nixos = _: {
      nixpkgs.overlays = [
        (final: prev: {
          neovim = inputs.nixvim-config.packages.${prev.stdenv.hostPlatform.system}.default;
        })
      ];
    };
  };
}
