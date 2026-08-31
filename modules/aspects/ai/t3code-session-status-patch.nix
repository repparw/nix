{
  den,
  ...
}:
{
  # Stopgap for stale t3code session statuses: threads kept showing
  # "running"/"working" after the provider session had actually stopped,
  # archived, or errored (tracked upstream as pingdotgg/t3code#2343 and
  # related). Provider-emitted session-set events are dispatched
  # unconditionally, so a late `session.state.changed` from opencode could
  # clobber a settled thread back to "running".
  #
  # Mirror the title-mirror guard pattern from PR #5941
  # (modules/aspects/ai/t3code-title-fix.patch): only propagate a session
  # status when the transition is legitimate — terminal states always land,
  # a ready thread may start a new turn, but an already-settled thread
  # ignores stale "running" echoes.
  #
  # Kept in its own aspect so scripts-free automation can remove the whole
  # workaround mechanically once the fix reaches our pin.
  den.aspects.ai.provides.t3code-session-status-patch = {
    nixos = {
      nixpkgs.overlays = [
        (final: prev: {
          t3code = prev.t3code.override {
            t3code-unwrapped = prev.t3code.unwrapped.overrideAttrs (old: {
              patches = (old.patches or [ ]) ++ [ ./t3code-session-status-fix.patch ];
            });
          };
        })
      ];
    };
  };
}
