{ inputs, ... }:
{
  flake-file.inputs.nixvim-config = {
    url = "github:repparw/nixvim-config";
    inputs.nixpkgs.follows = "nixpkgs";
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
