{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      registry = pkgs.writeText "upstream-gates.json" (builtins.readFile ../data/upstream-gates.json);
      upstreamGates = pkgs.writeShellApplication {
        name = "upstream-gates";
        runtimeInputs = with pkgs; [
          coreutils
          curl
          gawk
          git
          jq
        ];
        text = builtins.replaceStrings [ "@REGISTRY@" ] [ (lib.escapeShellArg (toString registry)) ] (
          builtins.readFile ./scripts/upstream-gates.sh
        );
      };
    in
    {
      packages.upstream-gates = upstreamGates;

      apps.upstream-gates = {
        type = "app";
        program = lib.getExe upstreamGates;
      };

      checks.upstream-gates = pkgs.runCommand "check-upstream-gates" { } ''
        ${lib.getExe upstreamGates} validate
        touch "$out"
      '';
    };
}
