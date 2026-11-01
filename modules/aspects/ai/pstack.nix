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

  den.aspects.ai.provides.pstack =
    let
      plugins =
        inputs.cursor-plugins
          or (throw "flake input `cursor-plugins` missing; run `nix run .#write-flake`");
    in
    {
      homeManager =
        {
          lib,
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
            };
        };
    };
}
