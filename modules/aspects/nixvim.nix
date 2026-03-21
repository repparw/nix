{ inputs, ... }:
{
  flake-file.inputs.nixvim = {
    url = "github:nix-community/nixvim";
    inputs.flake-parts.follows = "flake-parts";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.systems.follows = "systems";
  };

  flake-file.inputs.nixvim-config = {
    url = "github:repparw/nixvim-config";
    inputs.flake-parts.follows = "flake-parts";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.nixvim.follows = "nixvim";
  };

  den.aspects.nixvim = {
    nixos =
      { ... }:
      {
        nixpkgs.overlays = [
          (final: prev: {
            neovim = inputs.nixvim-config.packages.${prev.stdenv.hostPlatform.system}.default;
          })
        ];
      };
  };
}
