{ inputs, ... }:

let
  pkgsDir = ../pkgs;
  pkgs = builtins.attrNames (builtins.readDir pkgsDir);
  mkPkgOverlay = name: final: prev: {
    ${name} = final.callPackage (pkgsDir + "/${name}") { };
  };
in
{
  nixpkgs.overlays = [
    # `(final: prev: { xxx = prev.xxx.override { ... }; })`
    (final: prev: {
      neovim = inputs.nixvim-config.packages.${prev.stdenv.hostPlatform.system}.default;
    })
    inputs.firefox-addons.overlays.default
  ]
  ++ (map mkPkgOverlay pkgs);
}
