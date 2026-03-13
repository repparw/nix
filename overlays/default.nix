{ inputs, ... }:

let
  pkgsDir = ../pkgs;
  pkgs = builtins.attrNames (builtins.readDir pkgsDir);
  mkPkgOverlay = name: final: prev: {
    ${name} = final.callPackage (pkgsDir + "/${name}") { };
  };
  excludedPackages = [ "cfait" ]; # use nixpkgs-pr version for testing
  cfaitOverlay = final: prev: {
    cfait = inputs.nixpkgs-pr.legacyPackages.${prev.stdenv.hostPlatform.system}.cfait;
  };
in
{
  nixpkgs.overlays = [
    # `(final: prev: { xxx = prev.xxx.override { ... }; })`
    (final: prev: {
      neovim = inputs.nixvim-config.packages.${prev.stdenv.hostPlatform.system}.default;
      wshowkeys = prev.wshowkeys.overrideAttrs (old: {
        src = prev.fetchFromGitHub {
          owner = "repparw";
          repo = "wshowkeys";
          rev = "52d1191cc250d3a24b83f77ce23f23d498c23bb3";
          hash = "sha256-BkmB+/oG0tsAbvAjkoEAJxObjvg+mCENhM4EHDDXQAI=";
        };
      });
    })
    inputs.firefox-addons.overlays.default
    cfaitOverlay
  ]
  ++ (map mkPkgOverlay (builtins.filter (p: !builtins.elem p excludedPackages) pkgs));
}
