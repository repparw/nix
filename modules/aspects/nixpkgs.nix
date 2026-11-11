_: {
  den.aspects.nixpkgs = {
    nixos = _: {
      nixpkgs.config.allowUnfree = true;

      # nixpkgs#584667 fixes Codex's aws-lc-sys build. Until its merge
      # reaches nixos-unstable, provide the same system libraries on the
      # pinned package so T3 Code can build on both fleet architectures.
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
        })
      ];
    };
  };
}
