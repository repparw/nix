_: {
  den.aspects.nixpkgs = {
    nixos = _: {
      nixpkgs.config.allowUnfree = true;

      # nixpkgs#584667 fixes Codex's aws-lc-sys build. Until its merge
      # reaches nixos-unstable, provide the same system libraries on the
      # pinned package so T3 Code can build on both fleet architectures.
      #
      # The same pin forces "system aws-lc" for every aws-lc-sys crate
      # without adding the library to dependent packages (nixpkgs
      # #585435, fixed per-package upstream). The fleet's broken native
      # builds on that pin, with their upstream fixes to mirror:
      # - ashell (nixpkgs#585301): aws-lc in buildInputs; the build
      #   script then auto-detects the system install. Validated on
      #   x86_64 by the native smoke workflow.
      # - primp (nixpkgs#585435-class; no upstream fix yet): built via
      #   maturin, whose nativeBuildInputs omit pkg-config, so the
      #   forced system-library probes (aws-lc-sys, zstd-sys) find
      #   nothing and panic. Supply pkg-config and the system libs.
      #   ddgs depends on primp, so epsilon's closure fails to build
      #   without this, which stalls fleet preparation.
      nixpkgs.overlays = [
        (final: prev: {
          codex = prev.codex.overrideAttrs (old: {
            buildInputs =
              (old.buildInputs or [ ])
              ++ (with final; [
                aws-lc
                oniguruma
                sqlite
                zstd
              ]);
          });

          ashell = prev.ashell.overrideAttrs (old: {
            buildInputs =
              (old.buildInputs or [ ])
              ++ (with final; [
                aws-lc
              ]);
          });

          python313Packages = prev.python313Packages.overrideScope (
            pyFinal: pyPrev: {
              primp = pyPrev.primp.overrideAttrs (old: {
                buildInputs =
                  (old.buildInputs or [ ])
                  ++ (with final; [
                    aws-lc
                    zstd
                  ]);
                nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                  final.pkg-config
                ];
              });
            }
          );
        })
      ];
    };
  };
}
