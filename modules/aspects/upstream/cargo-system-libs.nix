{ den, ... }:
{
  # nixpkgs #537108 made cargoSetupHook export AWS_LC_SYS_USE_SYSTEM=1 and
  # unbundle other -sys crates, so crates now link the system library. codex
  # and voxtype picked up aws-lc-sys and onig_sys without the matching system
  # library in buildInputs and stopped building on the native runners
  # (codex tracked upstream as NixOS/nixpkgs#585124). Retire this overlay
  # once nixpkgs lands the buildInputs and flake.lock contains the fix.
  den.aspects.cargo-system-libs.nixos.nixpkgs.overlays = [
    (final: prev: {
      codex = prev.codex.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ final.aws-lc ];
      });
      voxtype = prev.voxtype.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ final.oniguruma ];
      });
    })
  ];
}
