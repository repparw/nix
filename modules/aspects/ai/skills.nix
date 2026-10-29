{
  den,
  inputs,
  ...
}:
{
  flake-file.inputs.cursor-plugins = {
    url = "github:cursor/plugins";
    flake = false;
  };

  # Declare shared coding-agent skills here. Repo-local skills under
  # .agents/skills remain scoped to this checkout; Hermes has its own skills.
  den.aspects.ai.provides.skills =
    let
      plugins =
        inputs.cursor-plugins
          or (throw "flake input `cursor-plugins` missing; run `nix run .#write-flake`");
    in
    {
      homeManager =
        { config, lib, ... }:
        let
          skillsDir = "${plugins}/pstack/skills";
          teamSkill = name: "${plugins}/cursor-team-kit/skills/${name}";
        in
        {
          # New directories in pstack are discovered automatically; the team
          # skills are explicit exceptions. Other aspects can add to this
          # OpenCode option, and Codex receives the merged effective set.
          programs.opencode.skills =
            lib.mapAttrs (name: _type: skillsDir + "/${name}") (
              lib.filterAttrs (_name: type: type == "directory") (builtins.readDir skillsDir)
            )
            // {
              deslop = teamSkill "deslop";
              control-cli = teamSkill "control-cli";
              control-ui = teamSkill "control-ui";
            };

          # T3 Code's Codex provider shares CODEX_HOME. Keep the CLI out of the
          # user profile: T3 Code launches the packaged engine itself.
          programs.codex = {
            enable = true;
            package = null;
            skills = config.programs.opencode.skills;
          };
        };
    };
}
