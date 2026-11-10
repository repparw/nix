{
  lib,
  fetchurl,
  upstream,
}:
let
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
  # Upstream v0.23.1 requires Node >=26. Preserve its pinned Node tool.
  pmPackages = lib.mapAttrs (_: fixPmArtifact) previous.pmPackages;
})
