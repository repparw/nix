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
          pkgs,
          ...
        }:
        let
          skillsDir = "${plugins}/pstack/skills";
          teamSkill = name: "${plugins}/cursor-team-kit/skills/${name}";

          # Upstream frontmatter `name: Poteto Mode` violates opencode skill
          # naming rules (lowercase, must match directory). Rebuild the skill
          # with a compliant frontmatter and the verbatim upstream body.
          # Playbooks/references/scripts are copied verbatim; SKILL.md links
          # them by relative path.
          potetoMode = pkgs.runCommand "pstack-poteto-mode" { } ''
            mkdir -p $out
            cp -r ${skillsDir}/poteto-mode/{playbooks,references,scripts} $out/
            {
              printf -- '---\nname: poteto-mode\ndescription: poteto agent style for rigorous engineering work; entry point routing to playbooks and principles. Use for /poteto-mode or any task needing rigor.\nlicense: MIT\n---\n'
              awk 'BEGIN { n = 0 } /^---[[:space:]]*$/ { n++; next } n >= 2 { print }' ${skillsDir}/poteto-mode/SKILL.md
            } > $out/SKILL.md
          '';
        in
        {
          programs.opencode.skills =
            lib.mapAttrs (name: _type: skillsDir + "/${name}") (
              lib.filterAttrs (name: type: type == "directory" && name != "poteto-mode") (
                builtins.readDir skillsDir
              )
            )
            // {
              poteto-mode = toString potetoMode;

              deslop = teamSkill "deslop";
              control-cli = teamSkill "control-cli";
              control-ui = teamSkill "control-ui";
            };
        };
    };
}
