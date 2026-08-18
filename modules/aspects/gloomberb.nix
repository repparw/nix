{ inputs, ... }:
{
  flake-file.inputs.gloomberb-nixpkgs = {
    url = "github:repparw/nixpkgs/gloomberb";
  };

  den.aspects.gloomberb = {
    nixos =
      { ... }:
      {
        nixpkgs.overlays = [
          (final: prev: {
            gloomberb = final.callPackage (
              inputs.gloomberb-nixpkgs + "/pkgs/by-name/gl/gloomberb/package.nix"
            ) { };
          })
        ];
      };

    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.gloomberb ];
      };
  };
}
