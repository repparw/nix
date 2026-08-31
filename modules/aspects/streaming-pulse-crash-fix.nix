{
  den,
  ...
}:
{
  # Stopgap for hgaiser/moonshine#182: a stalled pulse client (or a raced
  # timerfd wakeup) surfaces as EAGAIN, which moonshine 0.15.0 treats as
  # fatal (AudioEncoderStopped) and tears down the whole session — killing
  # the running game with it. Backports the two upstream fixes merged
  # 2026-08-25, after the v0.15.0 release nixpkgs ships:
  #   PR #184 "fix: don't crash the session when a pulse client stops reading"
  #   PR #167 "fix(audio): tolerate timerfd wakeups with no expirations"
  # Both cherry-picked onto v0.15.0 without conflicts. Remove this aspect
  # (and its .patch files) once a moonshine release containing both reaches
  # nixpkgs.
  den.aspects.streaming.provides.pulse-crash-fix = {
    nixos.nixpkgs.overlays = [
      (final: prev: {
        moonshine = prev.moonshine.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ./moonshine-pr184-pulse-client-stall.patch
            ./moonshine-pr167-timerfd-eagain.patch
          ];
        });
      })
    ];
  };
}
