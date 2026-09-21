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

      checks.agent-skills =
        pkgs.runCommand "check-agent-skills"
          {
            nativeBuildInputs = with pkgs; [
              bash
              git
              jq
              nix
              nodejs
              util-linux
            ];
          }
          ''
            export HOME=$(mktemp -d)
            export GIT_CONFIG_NOSYSTEM=1
            export AGENT_SKILLS_SOURCE=${../.}
            node --test \
              ${../.agents/skills/verify-nixos-config/scripts}/build.test.mjs \
              ${./aspects/ai/skills/watch-upstream/scripts}/run.test.mjs
            touch "$out"
          '';
    };
}
