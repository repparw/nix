{
  den,
  ...
}:
{
  # Stopgap for pingdotgg/t3code#5941 (merged 2026-08-15, first stable 0.0.34):
  # upstream >= 0.0.31 delegates OpenCode session titles to the provider, but
  # opencode auto-names sessions "New session - <ts>", which clobbers the real
  # thread title. Mirror the upstream PR: only accept a provider title while
  # the thread still has its default title, and filter opencode's placeholder.
  #
  # Kept in its own aspect so scripts-free automation can remove the whole
  # workaround mechanically once the fix reaches our pin — see
  # ~/.local/bin/watch-t3code-title-fix.sh (intentionally outside git).
  den.aspects.ai.provides.t3code-title-patch = {
    nixos = {
      nixpkgs.overlays = [
        (final: prev: {
          t3code = prev.t3code.override {
            t3code-unwrapped = prev.t3code.unwrapped.overrideAttrs (old: {
              patches = (old.patches or [ ]) ++ [ ./t3code-title-fix.patch ];
            });
          };
        })
      ];
    };
  };
}
