{
  lib,
  callPackage,
  python312,
  runCommand,
  upstream,
}:
let
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
