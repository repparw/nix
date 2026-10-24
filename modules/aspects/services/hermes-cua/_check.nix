{ pkgs, source }:
let
  plugin = pkgs.callPackage ../../../_packages/hermes-cua-spaces.nix { };
  python = pkgs.python3.withPackages (ps: [ ps.ruamel-yaml ]);
  gate =
    ref: source: version:
    import ./_integration.nix {
      inherit (pkgs) lib;
      inherit source ref;
      runtime = { inherit version; };
    };
  apiFixture = ./fixtures/supported;
  oldApiFixture = ./fixtures/old;
  current = gate "v0.22.2" apiFixture "0.7.0";
  supported = gate "v0.22.3" apiFixture "0.7.0";
in
assert !current.ready && current.settings == { };
assert !(gate "v0.22.3" oldApiFixture "0.7.0").ready;
assert !(gate "v0.22.3" apiFixture "0.6.0").ready;
assert !(gate "v0.22.3" apiFixture "0.8.0").ready;
assert !(gate "main" apiFixture "0.7.0").ready;
assert supported.ready && supported.settings.terminal.backend == "cua";
assert supported.settings.plugins.entries.cua-spaces.enabled;
assert supported.settings.plugins.entries.cua-spaces.settings.space != "create";
pkgs.runCommand "check-hermes-cua-policy"
  {
    nativeBuildInputs = [ python ];
    CUA_PLUGIN = plugin;
    PYTHONPATH = "${source}:${plugin}";
  }
  ''
    export HOME=$TMPDIR
    python3 ${./test_policy.py} -v
    touch $out
  ''
