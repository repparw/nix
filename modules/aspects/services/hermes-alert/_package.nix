{ pkgs }:
let
  source = pkgs.writeText "grafana-alert-triage.py" (builtins.readFile ./triage.py);
in
{
  receiver = pkgs.writeShellApplication {
    name = "grafana-alert-triage";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${source} "$@"
    '';
  };
  gate = pkgs.writeText "alert_triage_cron.py" ''
    import runpy
    import sys
    sys.argv = [${builtins.toJSON (toString source)}, "gate", "--state", "/var/lib/hermes/.hermes/alert-triage"]
    runpy.run_path(${builtins.toJSON (toString source)}, run_name="__main__")
  '';
  enroll = pkgs.writeText "alert_triage_enroll.py" (builtins.readFile ./enroll.py);
  check = pkgs.runCommand "check-grafana-alert-triage" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    cp ${./triage.py} triage.py
    cp ${./test_triage.py} test_triage.py
    python3 test_triage.py ./triage.py
    touch $out
  '';
}
