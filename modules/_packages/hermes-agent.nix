{
  lib,
  callPackage,
  nodejs_24,
  upstream,
}:
let
  # Hermes accepts Node >=22.22.0; npm 12 accepts Node ^24.15.0.
  # Node 26 currently fails on ARM (NixOS/nixpkgs#568974).
  nodejs =
    assert lib.versionAtLeast nodejs_24.version "24.15.0";
    nodejs_24;
in
upstream.override {
  callPackage =
    path: args:
    callPackage path (
      args
      // lib.optionalAttrs (builtins.baseNameOf path == "lib.nix") {
        nodejs_26 = nodejs;
        callPackage =
          npmPath: npmArgs:
          callPackage npmPath (
            npmArgs
            // lib.optionalAttrs (builtins.baseNameOf npmPath == "npm-12-0-2.nix") {
              nodejs_26 = nodejs;
            }
          );
      }
    );
}
