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
          noCommentsSource = pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/backnotprop/pstack/25abb38559ddbabec563646224d09eff9a250eca/skills/no-comments/SKILL.md";
            hash = "sha256-pyUFl3HRV3/Fn70mbi91/n9UeiOj3MEFJFnbVK4QwMI=";
          };
          noCommentsReference = pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/backnotprop/pstack/25abb38559ddbabec563646224d09eff9a250eca/skills/no-comments/references/comment-sicko.md";
            hash = "sha256-c8C8uMJYmBExwA8JwsVuMAxyJYA71OEJPvQTYuAHPZg=";
          };
          noCommentsSkill = pkgs.runCommand "pstack-no-comments-skill" { } ''
            mkdir -p "$out/references"
            cp ${noCommentsSource} "$out/SKILL.md"
            cp ${noCommentsReference} "$out/references/comment-sicko.md"
          '';
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
              no-comments = "${noCommentsSkill}";
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
