lib: prev:
  # wpaperd 1.3.0 segfaults on every monitor hotplug: niri can still
  # dispatch frame/scale/transform events for a wl_surface that
  # output_destroyed() already removed, and surface_from_wl_surface()
  # used .expect() on that lookup. Upstream fixed it in
  # danyspin97/wpaperd@442b962 ("avoid panic when Wayland events arrive
  # after output removal"), which fixes #190 and is in no release yet.
  # Matched on the exact version so a bump drops the patch instead of
  # failing patchPhase.
prev.wpaperd.overrideAttrs (old: {
              patches =
                (old.patches or [ ]) ++ lib.optional (old.version == "1.3.0") ../wpaperd-output-removal-race.patch;
            })
