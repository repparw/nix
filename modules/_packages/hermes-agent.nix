{
  lib,
  callPackage,
  nodejs_24,
  upstream,
}:
let
  # Hermes accepts Node >=22.22.0; npm 12 accepts Node ^24.15.0.
  # Keep the fleet's patched Node runtime when upstream selects PM artifacts.
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
        pmPackages = args.pmPackages // {
          node = nodejs;
        };
      }
    );
}
