{
  outputs =
    { self }:
    let
      repo = builtins.getFlake (builtins.getEnv "UPSTREAM_PROBE_REPO");
      pkgs = repo.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
      package =
        value:
        pkgs.stdenv.mkDerivation {
          pname = "watcher-probe-fixture";
          version = "1.0";
          src = pkgs.writeTextDir "value" value;
          patches = [ ./probe.patch ];
          buildPhase = "echo unexpected-compilation >&2; exit 1";
          doInstallCheck = true;
          nativeInstallCheckInputs = [ pkgs.versionCheckHook ];
          versionCheckProgramArg = "--version";
          meta.mainProgram = "watcher-probe-fixture";
        };
    in
    {
      valid = package "before\n";
      incompatible = package "different-source\n";
    };
}
