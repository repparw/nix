{
  den,
  ...
}:
{
  # Stopgap for NixOS/nixpkgs#555814 ("split desktop app into
  # t3code-desktop"), until it merges and reaches our pin:
  #
  # - `t3code` wraps only `bin/t3`; its closure carries no Electron/GTK.
  # - `t3code-desktop` owns the Electron dependency and the launcher.
  #
  # The unwrapped build already installs the full monorepo (including the
  # desktop bundle under libexec/), so stripping here is just deleting the
  # launcher and icons the upstream PR moved into `t3code-desktop`.
  #
  # Composes with provides.t3code-title-patch in either overlay order: both
  # derive their changes from `prev.t3code.unwrapped` rather than replacing
  # each other's work.
  den.aspects.ai.provides.t3code-split = {
    nixos = {
      nixpkgs.overlays = [
        (final: prev: {
          t3code = prev.t3code.override {
            t3code-unwrapped = prev.t3code.unwrapped.overrideAttrs (old: {
              postFixup = (old.postFixup or "") + ''
                rm -rf "$out/bin/t3code-desktop" \
                  "$out/share/applications" "$out/share/icons"
              '';
              meta = (old.meta or { }) // {
                mainProgram = "t3";
              };
            });
          };

          # Lives outside modules/ because import-tree auto-imports every
          # .nix there as a NixOS module, which would call this package
          # builder with module args.
          t3code-desktop = prev.callPackage ../../../packages/t3code-desktop/package.nix {
            t3code = final.t3code;
          };
        })
      ];
    };
  };
}
