{
  pkgs,
  knownWaits ? { },
}:
let
  source = pkgs.runCommand "hermes-crash-triage-source" { } ''
    mkdir -p "$out"
    cp ${./triage.py} "$out/triage.py"
    cp ${../hermes_event_ingest.py} "$out/hermes_event_ingest.py"
  '';
  entrypoint = "${source}/triage.py";
  knownWaitsFile = pkgs.writeText "hermes-crash-known-waits.json" (builtins.toJSON knownWaits);
in
{
  ingest = pkgs.writeShellApplication {
    name = "hermes-crash-ingest";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${entrypoint} ingest --home /home/repparw/services/hermes/.hermes
    '';
  };
  gate = pkgs.writeText "crash_triage_cron.py" ''
    import runpy
    import sys
    sys.path.insert(0, ${builtins.toJSON (toString source)})
    sys.argv = [${builtins.toJSON entrypoint}, "gate", "--known-waits", ${builtins.toJSON (toString knownWaitsFile)}]
    runpy.run_path(${builtins.toJSON entrypoint}, run_name="__main__")
  '';
  enroll = pkgs.writeText "crash_triage_enroll.py" (builtins.readFile ./enroll.py);
  check =
    pkgs.runCommand "check-hermes-crash-triage"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        cp ${./triage.py} triage.py
        cp ${../hermes_event_ingest.py} hermes_event_ingest.py
        cp ${./test_triage.py} test_triage.py
        python3 -m unittest -v test_triage
        touch $out
      '';
}
