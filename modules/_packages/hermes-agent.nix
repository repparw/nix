{
  lib,
  callPackage,
  nodejs_24,
  python312,
  runCommand,
  upstream,
}:
let
  # Hermes accepts Node >=22.22.0; npm 12 accepts Node ^24.15.0.
  # Node 26 currently fails on ARM (NixOS/nixpkgs#568974).
  nodejs =
    assert lib.versionAtLeast nodejs_24.version "24.15.0";
    nodejs_24;
  # Append the code patch after the workspace overlay creates hermes-agent.
  # Keep lock metadata unpatched so evaluating another host needs no build.
  patchedPythonSet =
    packageSet:
    packageSet
    // {
      overrideScope =
        overlay:
        (packageSet.overrideScope overlay).overrideScope (
          _final: prev: {
            hermes-agent = prev.hermes-agent.overrideAttrs (old: {
              patches = (old.patches or [ ]) ++ [ ./hermes-auxiliary-routing.patch ];
            });
          }
        );
    };
  package = upstream.override {
    callPackage =
      path: args:
      callPackage path (
        args
        // lib.optionalAttrs (builtins.baseNameOf path == "python.nix") {
          callPackage =
            pythonPath: pythonArgs:
            let
              result = callPackage pythonPath pythonArgs;
            in
            if result ? mkVirtualEnv then patchedPythonSet result else result;
        }
        // lib.optionalAttrs (builtins.baseNameOf path == "lib.nix") {
          nodejs_26 = nodejs;
          callPackage =
            npmPath: npmArgs:
            callPackage npmPath (
              npmArgs
              // lib.optionalAttrs (builtins.baseNameOf npmPath == "npm-12-0-2.nix") {
                nodejs_26 = nodejs;
              }
            );
        }
      );
  };
  testPython = python312.withPackages (ps: [ ps.pytest ]);
in
package.overrideAttrs (old: {
  passthru = old.passthru // {
    tests = (old.passthru.tests or { }) // {
      auxiliary-routing = runCommand "hermes-auxiliary-routing-test" { } ''
        export HERMES_HOME="$TMPDIR/hermes"
        export PYTHONDONTWRITEBYTECODE=1
        export PYTHONPATH=${package.hermesVenv}/${python312.sitePackages}
        ${testPython}/bin/python3 -m pytest ${./test_hermes_auxiliary_routing.py} -q -p no:cacheprovider
        touch "$out"
      '';
    };
  };
})
