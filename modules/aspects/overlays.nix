{
  den,
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
          in
          (map mkPkgOverlay allPkgs);
      };
  };
}
