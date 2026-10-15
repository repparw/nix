# Temporary alpha-only test build tracking #147. Carries upstream PR227 plus
# the local reload guard so the running service behaves exactly like the
# drop-in experiment it replaces. Retire via the moonshine-pr227 cleanup
# candidate once the pinned upstream source contains both; do not rebase
# these patches onto a moved Moonshine version — publish the cleanup instead.
{
  moonshine,
}:

moonshine.overrideAttrs (old: {
  pname = "moonshine-pr227-reload-fix";
  patches = (old.patches or [ ]) ++ [
    ./upstream-227.patch
    ./reload-fix.patch
  ];
  # The validated test build ran the moonshine-core test suite; keep it as
  # part of the package so every rebuild re-proves the guard.
  doCheck = true;
  cargoTestFlags = [
    "-p"
    "moonshine-core"
  ];
})
