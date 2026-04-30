{
  inputs,
  ...
}:
{
  den.aspects.overlays = {
    includes = [ ];

    nixos =
      { pkgs, ... }:
      {
        nixpkgs.overlays =
          let
            pkgsDir = ../../pkgs;
            allPkgs =
              if builtins.pathExists pkgsDir then builtins.attrNames (builtins.readDir pkgsDir) else [ ];
            mkPkgOverlay = name: final: prev: {
              ${name} = final.callPackage (pkgsDir + "/${name}") { };
            };
            cfaitOverlay = final: prev: {
              inherit (inputs.nixpkgs-pr.legacyPackages.${prev.stdenv.hostPlatform.system}) cfait;
            };
          in
          [
            (final: prev: {
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
            (final: prev: {
              firefox-addons = final.lib.mapAttrs (
                name: pkg:
                pkg.overrideAttrs (old: {
                  meta = old.meta // {
                    license = final.lib.licenses.unfree;
                  };
                })
              ) prev.firefox-addons;
            })
            cfaitOverlay
          ]
          ++ (map mkPkgOverlay allPkgs);
      };
  };
}
