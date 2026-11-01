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
  flake-file.inputs.mattpocock-skills = {
    url = "github:mattpocock/skills";
    flake = false;
  };

  den.aspects.ai.provides.skills =
    let
      plugins =
        inputs.cursor-plugins
          or (throw "flake input `cursor-plugins` missing; run `nix run .#write-flake`");
    in
    {
      homeManager =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          skillsDir = "${plugins}/pstack/skills";
          teamSkill = name: "${plugins}/cursor-team-kit/skills/${name}";
          excludedSkills = [
            "make-bot-ui"
            "poteto-help"
            "reflect"
            "setup-pstack"
          ];
          pocockSource = pkgs.applyPatches {
            name = "mattpocock-skills";
            src = inputs.mattpocock-skills;
            patches = [ ./patches/mattpocock-skills.patch ];
          };
        in
        {
          programs.opencode.skills =
            lib.mapAttrs (name: _: skillsDir + "/${name}") (
              lib.filterAttrs (name: type: type == "directory" && !(builtins.elem name excludedSkills)) (
                builtins.readDir skillsDir
              )
            )
            // {
              deslop = teamSkill "deslop";
              control-cli = teamSkill "control-cli";
              control-ui = teamSkill "control-ui";
              retro = "${pocockSource}/skills/engineering/retro";
              writing-for-agents = "${pocockSource}/skills/productivity/writing-for-agents";
              diagnosing-bugs = "${pocockSource}/skills/engineering/diagnosing-bugs";
            };

          programs.codex = {
            enable = true;
            package = null;
            skills = config.programs.opencode.skills;
          };
        };
    };
}
