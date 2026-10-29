{ den, lib, ... }:
{
  # Upstream danyspin97/wpaperd@442b962 fixes stale Wayland surface events
  # after output removal; the pinned package still uses pre-fix 1.3.0.
  den.aspects.gui.provides.niri.nixos.nixpkgs.overlays = [
    (_final: prev: {
      wpaperd = prev.wpaperd.overrideAttrs (old: {
        patches =
          (old.patches or [ ]) ++ lib.optional (old.version == "1.3.0") ./wpaperd-output-removal-race.patch;
      });
    })
  ];
}
