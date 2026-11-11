_: {
  den.aspects.nixpkgs = {
    nixos = _: {
      nixpkgs.config.allowUnfree = true;

      # nixpkgs#584667 fixes Codex's aws-lc-sys build. Until that merge
      # reaches nixos-unstable, provide the same system libraries on the
      # pinned package on Alpha. Keep ARM unchanged while its native build
      # remains unverified.
      nixpkgs.overlays = [
        (final: prev: {
          codex =
            if prev.stdenv.hostPlatform.isx86_64 then
              prev.codex.overrideAttrs (old: {
                buildInputs =
                  (old.buildInputs or [ ])
                  ++ (with final; [
                    aws-lc
                    oniguruma
                    sqlite
                    zstd
                  ]);
              })
            else
              prev.codex;
        })
      ];
    };
  };
}
