{
  pkgs,
  knownWaits ? { },
}:
let
  source = pkgs.writeText "hermes-package-triage.py" (builtins.readFile ./triage.py);
  knownWaitsFile = pkgs.writeText "hermes-package-known-waits.json" (builtins.toJSON knownWaits);
in
{
  ingest = pkgs.writeShellApplication {
    name = "hermes-package-ingest";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${source} ingest --home /home/repparw/services/hermes/.hermes
    '';
  };
  gate = pkgs.writeText "package_triage_cron.py" ''
    import runpy
    import sys
    sys.argv = [${builtins.toJSON (toString source)}, "gate", "--known-waits", ${builtins.toJSON (toString knownWaitsFile)}]
    runpy.run_path(${builtins.toJSON (toString source)}, run_name="__main__")
  '';
  enroll = pkgs.writeText "package_triage_enroll.py" (builtins.readFile ./enroll.py);
  check =
    pkgs.runCommand "check-hermes-package-triage"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        cp ${./triage.py} triage.py
        cp ${./test_triage.py} test_triage.py
        python3 -m unittest -v test_triage
        python3 ${../../../scripts/package-update-event.test.py} ${../../../scripts/package-update-event.py}
        touch $out
      '';
}
