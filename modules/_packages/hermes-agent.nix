{
  lib,
  callPackage,
  fetchurl,
  nodejs_24,
  upstream,
}:
let
  # Hermes accepts Node >=22.22.0; npm 12 accepts Node ^24.15.0.
  # Keep the fleet's patched Node runtime when upstream selects PM artifacts.
  nodejs =
    assert lib.versionAtLeast nodejs_24.version "24.15.0";
    nodejs_24;

  # Hermes v0.23.1 patches patchelf for an ELF interpreter/RPATH regression
  # introduced after the nixpkgs pin's 0.15.2. Supply the upstream patch's
  # intended 0.19.2 source to its own PM artifact builders only.
  patchelfSource = fetchurl {
    url = "https://github.com/NixOS/patchelf/releases/download/0.19.2/patchelf-0.19.2.tar.bz2";
    hash = "sha256-1K2aTlxongkRnOLzCpSw6LT5jHhZASPqIWZeNMaSiAE=";
  };
  fixPmArtifact =
    artifact:
    artifact.overrideAttrs (old: {
      nativeBuildInputs = map (
        tool:
        if (tool.pname or null) == "patchelf" && (tool.version or null) == "0.15.2" then
          tool.overrideAttrs (_: {
            version = "0.19.2";
            src = patchelfSource;
          })
        else
          tool
      ) (old.nativeBuildInputs or [ ]);
    });
in
upstream.override (previous: {
  pmPackages = lib.mapAttrs (_: fixPmArtifact) previous.pmPackages;
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
})
